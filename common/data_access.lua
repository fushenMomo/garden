local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local const = require "common.const"
local util = require "common.util"
local DBDef = require "common.db_keys_define"
local row_cache = require "common.row_cache"

local M = {}

local TABLE_MAP = {
    player_data = DBDef.Table.player.player_data,
    role_base = DBDef.Table.role.role_base,
    role_data = DBDef.Table.role.role_data,
    role_guild = DBDef.Table.role.role_guild,
    bag_slots = DBDef.Table.role.bag_slots,
    bag = DBDef.Table.role.bag,
}

local function is_multi_row(table_def)
    return DBDef.is_multi_row(table_def)
end

local function mysql_addr()
    return skynet.address(".db_game")
end

local function global_mysql_addr()
    return skynet.address(".db_global")
end

local function redis_addr()
    return skynet.address(".redis")
end

local function resolve_mysql_table(table_def, keys_or_row, opts)
    return DBDef.resolve_table_name(table_def, keys_or_row, opts)
end

local function get_role_table_index()
    local addr = global_mysql_addr()
    if not addr then
        return DBDef.tableIndexBase
    end
    local ret, result = skynet.call(addr, "lua", "select_all", "game_global")
    if ret and result and result[1] then
        local idx = tonumber(result[1].role_table_index)
        if idx and idx >= DBDef.tableIndexBase then
            return idx
        end
    end
    return DBDef.tableIndexBase
end

local function ensure_mysql_table(addr, table_def, mysql_table)
    local base_table = table_def.tableName .. "_" .. DBDef.tableIndexBase
    logger.info("ensure_mysql_table, base_table=%s, mysql_table=%s", base_table, mysql_table)
    if mysql_table ~= base_table then
        skynet.call(addr, "lua", "create_table", mysql_table, base_table)
    end
end

function M.get_table_def(table_name)
    return TABLE_MAP[table_name]
end

local function encode_db_row_for_mysql(table_def, db_row)
    local encoded = {}
    for k, v in pairs(db_row) do
        encoded[k] = v
    end
    for i, db_field in ipairs(table_def.field) do
        local v = encoded[db_field]
        if v ~= nil then
            local dtype = table_def.dataType[i]
            if dtype == DBDef.DataType.table or dtype == DBDef.DataType.json then
                encoded[db_field] = util.serialize(v)
            end
        end
    end
    return encoded
end

local function decode_db_row_from_mysql(table_def, db_row)
    if not db_row then
        return nil
    end
    local decoded = {}
    for k, v in pairs(db_row) do
        decoded[k] = v
    end
    for i, db_field in ipairs(table_def.field) do
        local v = decoded[db_field]
        if v ~= nil then
            local dtype = table_def.dataType[i]
            if dtype == DBDef.DataType.table or dtype == DBDef.DataType.json then
                decoded[db_field] = util.unserialize(v)
            end
        end
    end
    return decoded
end

local function build_conditions(table_def, row)
    local conditions = {}
    for _, idx in ipairs(table_def.updateKey) do
        local field = table_def.field[idx]
        conditions[field] = row[field]
    end
    return conditions
end

local function filter_changed_row(table_def, row, changed_fields)
    if not changed_fields or not next(changed_fields) then
        return row
    end
    local updatable = {}
    local start_idx = table_def.updateIndex or 1
    for i = start_idx, #table_def.field do
        updatable[DBDef.logic_field(table_def, table_def.field[i])] = true
    end
    local partial = {}
    for _, logic_field in ipairs(changed_fields) do
        if updatable[logic_field] and row[logic_field] ~= nil then
            partial[logic_field] = row[logic_field]
        end
    end
    if not next(partial) then
        return row
    end
    return partial
end

function M.load_from_mysql(table_def, keys)
    local addr = mysql_addr()
    if not addr then
        return nil
    end
    local db_keys = DBDef.to_db_row(table_def, keys)
    local mysql_table = resolve_mysql_table(table_def, db_keys)
    ensure_mysql_table(addr, table_def, mysql_table)
    local ret, result = skynet.call(
        addr,
        "lua",
        "select_one_by_conditions",
        mysql_table,
        db_keys
    )
    if ret and result then
        return DBDef.to_logic_row(table_def, decode_db_row_from_mysql(table_def, result))
    end
    return nil
end

function M.load_many_from_mysql(table_def, keys)
    local addr = mysql_addr()
    if not addr then
        return nil
    end
    local db_keys = DBDef.to_db_row(table_def, keys)
    local query_field = table_def.field[table_def.queryKey]
    local query_value = db_keys[query_field]
    if query_value == nil then
        return nil
    end
    local mysql_table = resolve_mysql_table(table_def, db_keys)
    ensure_mysql_table(addr, table_def, mysql_table)
    local ret, result = skynet.call(
        addr,
        "lua",
        "select_by_conditions",
        mysql_table,
        { [query_field] = query_value },
        nil,
        0,
        table_def.limit
    )
    if not ret or not result then
        return {}
    end
    local rows = {}
    for _, db_row in ipairs(result) do
        table.insert(rows, DBDef.to_logic_row(table_def, decode_db_row_from_mysql(table_def, db_row)))
    end
    return rows
end

function M.insert_to_mysql(table_def, row)
    local addr = mysql_addr()
    if not addr then
        return false
    end
    local db_row = encode_db_row_for_mysql(table_def, DBDef.to_db_row(table_def, row))
    local opts = {}
    if table_def.tableName == "role_base" then
        local raw = DBDef.to_db_row(table_def, row)
        if not raw.dbid or raw.dbid == 0 then
            opts.table_suffix = get_role_table_index()
        end
    end
    local mysql_table = resolve_mysql_table(table_def, row, opts)
    ensure_mysql_table(addr, table_def, mysql_table)
    local ret, insert_id = skynet.call(addr, "lua", "insert", mysql_table, db_row)
    if ret then
        if table_def.field[1] == "dbid" and insert_id and insert_id > 0 then
            row.dbid = insert_id
        end
        return true, insert_id
    end
    return false
end

function M.update_to_mysql(table_def, row, changed_fields)
    local addr = mysql_addr()
    if not addr then
        return false
    end
    local db_row = DBDef.to_db_row(table_def, row)
    local conditions = build_conditions(table_def, db_row)
    local update_row = filter_changed_row(table_def, row, changed_fields)
    local encoded_row = encode_db_row_for_mysql(table_def, DBDef.to_db_row(table_def, update_row))
    local mysql_table = resolve_mysql_table(table_def, db_row)
    ensure_mysql_table(addr, table_def, mysql_table)
    local ret = skynet.call(
        addr,
        "lua",
        "update_by_conditions",
        mysql_table,
        conditions,
        encoded_row
    )
    return ret
end

--[[
    三层读取:
    Ⅰ. opts.memory  — 在线玩家内存数据（L1）
    Ⅱ. Redis 行缓存 — 离线玩家缓存（L2）
    Ⅲ. MySQL        — 缓存未命中时回源并回填 L2
]]
function M.load(table_name, keys, opts)
    opts = opts or {}
    local table_def = TABLE_MAP[table_name]
    if not table_def then
        logger.error("data_access.load unknown table, name=%s", table_name)
        return nil
    end

    if is_multi_row(table_def) then
        local db_keys = DBDef.to_db_row(table_def, keys)
        for _, idx in ipairs(table_def.updateKey) do
            local field = table_def.field[idx]
            if db_keys[field] == nil then
                logger.error(
                    "data_access.load multi-row table needs full keys, use load_many, table=%s",
                    table_name
                )
                return nil
            end
        end
    end

    if opts.memory then
        return opts.memory
    end

    local db_keys = DBDef.to_db_row(table_def, keys)
    local row_key = DBDef.build_redis_key(table_def, db_keys)

    local cached = row_cache.get_row(table_def, row_key)
    if cached then
        logger.info("data_access.load cached, table_name=%s, row_key=%s", table_name, row_key)
        return cached
    end

    local row = M.load_from_mysql(table_def, db_keys)
    if row then
        logger.info("data_access.load mysql, table_name=%s, row_key=%s", table_name, row_key)
        row_cache.set_row(table_def, row_key, row)
    end
    return row
end

--[[
    多行表按 queryKey 批量读取（如 bag_slots 按 parentDBID 加载全部格子）。
    每行独立走 Redis 行缓存，未命中则回源 MySQL 并回填。
]]
function M.load_many(table_name, keys, opts)
    opts = opts or {}
    local table_def = TABLE_MAP[table_name]
    if not table_def then
        logger.error("data_access.load_many unknown table, name=%s", table_name)
        return nil
    end
    if not is_multi_row(table_def) then
        logger.error("data_access.load_many table is not multi-row, name=%s", table_name)
        return nil
    end

    if opts.memory then
        return opts.memory
    end

    local rows = M.load_many_from_mysql(table_def, keys) or {}
    local result = {}
    for _, row in ipairs(rows) do
        local row_key = DBDef.build_redis_key(table_def, row)
        local cached = row_cache.get_row(table_def, row_key)
        if cached then
            logger.info("data_access.load_many cached, table_name=%s, row_key=%s", table_name, row_key)
            table.insert(result, cached)
        else
            logger.info("data_access.load_many mysql, table_name=%s, row_key=%s", table_name, row_key)
            row_cache.set_row(table_def, row_key, row)
            table.insert(result, row)
        end
    end
    return result
end

--[[
    写入缓存层并标记脏数据，由 data_sync 异步落库。
    在线场景下由 world_agent 同步更新 L1 内存。
]]
function M.save(table_name, row, changed_fields)
    local table_def = TABLE_MAP[table_name]
    if not table_def or not row then
        return false
    end
    local row_key = DBDef.build_redis_key(table_def, row)
    row_cache.set_row(table_def, row_key, row)
    local cached = row_cache.get_row(table_def, row_key)
    row_cache.mark_dirty(row_key, cached, changed_fields)
    return true
end

function M.insert(table_name, row)
    local table_def = TABLE_MAP[table_name]
    if not table_def or not row then
        return false
    end
    local ok, insert_id = M.insert_to_mysql(table_def, row)
    if not ok then
        return false
    end
    local row_key = DBDef.build_redis_key(table_def, row)
    row_cache.set_row(table_def, row_key, row)
    return true, insert_id
end

function M.set_online(server_id, acc_id, login_time)
    local addr = redis_addr()
    if not addr then
        return false
    end
    skynet.call(
        addr,
        "lua",
        "set",
        string.format(const.redis_key.online, server_id, acc_id),
        "1"
    )
    skynet.call(
        addr,
        "lua",
        "zadd",
        string.format(const.redis_key.last_login, server_id),
        acc_id,
        login_time or os.time()
    )
    return true
end

function M.set_offline(server_id, acc_id)
    local addr = redis_addr()
    if not addr then
        return false
    end
    skynet.call(
        addr,
        "lua",
        "del",
        string.format(const.redis_key.online, server_id, acc_id)
    )
    return true
end

function M.is_online(server_id, acc_id)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local ret = skynet.call(
        addr,
        "lua",
        "exists",
        string.format(const.redis_key.online, server_id, acc_id)
    )
    return ret and ret == 1
end

function M.build_row_key(table_name, row)
    local table_def = TABLE_MAP[table_name]
    if not table_def then
        return nil
    end
    return DBDef.build_redis_key(table_def, row)
end

function M.collect_bag_slot_row_keys(parent_dbid)
    local keys = {}
    if not parent_dbid or parent_dbid == 0 then
        return keys
    end
    local table_def = TABLE_MAP.bag_slots
    local rows = M.load_many_from_mysql(table_def, { parentDBID = parent_dbid }) or {}
    for _, row in ipairs(rows) do
        local row_key = M.build_row_key("bag_slots", row)
        if row_key then
            table.insert(keys, row_key)
        end
    end
    return keys
end

function M.collect_player_row_keys(player_data, role_base, role_data)
    local keys = {}
    if player_data then
        local k = M.build_row_key("player_data", player_data)
        if k then
            table.insert(keys, k)
        end
    end
    if role_data then
        local base_key = M.build_row_key("role_base", role_base)
        if base_key then
            table.insert(keys, base_key)
        end
        local data_key = M.build_row_key("role_data", { parentDBID = role_data.parentDBID })
        if data_key then
            table.insert(keys, data_key)
        end
        local guild_key = M.build_row_key("role_guild", { parentDBID = role_data.parentDBID })
        if guild_key then
            table.insert(keys, guild_key)
        end
        local bag_key = M.build_row_key("bag", { parentDBID = role_data.parentDBID })
        if bag_key then
            table.insert(keys, bag_key)
        end
        local slot_keys = M.collect_bag_slot_row_keys(role_data.parentDBID)
        for _, slot_key in ipairs(slot_keys) do
            table.insert(keys, slot_key)
        end
    end
    return keys
end

function M.query_stale_login_players(server_id, cutoff_time)
    local addr = redis_addr()
    if not addr then
        return {}
    end
    local key = string.format(const.redis_key.last_login, server_id)
    return skynet.call(addr, "lua", "zrangebyscore", key, 0, cutoff_time) or {}
end

function M.remove_last_login(server_id, acc_id)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local key = string.format(const.redis_key.last_login, server_id)
    skynet.call(addr, "lua", "zrem", key, acc_id)
    return true
end

function M.build_row_keys_for_evict(server_id, act_id, player_data)
    local keys = {}
    local seen = {}
    local function add(key)
        if key and not seen[key] then
            seen[key] = true
            table.insert(keys, key)
        end
    end

    add(string.format(const.redis_key.player_data, server_id, act_id))
    if not player_data then
        return keys
    end

    for _, slot in ipairs({ "role1", "role2", "role3", "role4" }) do
        local dbid = player_data[slot]
        if dbid and dbid ~= 0 then
            add(M.build_row_key("role_base", { dbid = dbid }))
            add(M.build_row_key("role_data", { parentDBID = dbid }))
            add(M.build_row_key("role_guild", { parentDBID = dbid }))
            add(M.build_row_key("bag", { parentDBID = dbid }))
            for _, slot_key in ipairs(M.collect_bag_slot_row_keys(dbid)) do
                add(slot_key)
            end
        end
    end
    return keys
end


function M.evict_player_cache(server_id, act_id)
    if M.is_online(server_id, act_id) then
        return "online"
    end

    local player_def = TABLE_MAP.player_data
    local player_row_key = string.format(const.redis_key.player_data, server_id, act_id)
    local player_data = row_cache.get_row(player_def, player_row_key)
    if not player_data then
        M.remove_last_login(server_id, act_id)
        return "no_cache"
    else
        local row_keys = M.build_row_keys_for_evict(server_id, act_id, player_data)
        for _, row_key in ipairs(row_keys) do
            if row_cache.exists(row_key) then
                row_cache.del_row(row_key)
            end
        end
        M.remove_last_login(server_id, act_id)
        return "ok"
    end
end

--[[
在线? → 跳过
  ↓
读 player_data 缓存（缺失则 MySQL 兜底拿 role 槽位）
  ↓
收集 p + rbase + rdata（多角色）
  ↓
无任何行缓存? → zrem 索引，标记 no_cache
  ↓
逐 key flush_row（失败则中止，下轮重试）
  ↓
逐 key del_row
  ↓
zrem last_login

function M.evict_player_cache(server_id, act_id)
    if M.is_online(server_id, act_id) then
        return "online"
    end

    local player_def = TABLE_MAP.player_data
    local player_row_key = string.format(const.redis_key.player_data, server_id, act_id)
    local player_data = row_cache.get_row(player_def, player_row_key)
    if not player_data then
        player_data = M.load_from_mysql(player_def, { act_id = act_id, server_id = server_id })
    end

    local row_keys = M.build_row_keys_for_evict(server_id, act_id, player_data)
    local has_cache = false
    for _, row_key in ipairs(row_keys) do
        if row_cache.exists(row_key) then
            has_cache = true
            break
        end
    end
    if not has_cache then
        M.remove_last_login(server_id, act_id)
        return "no_cache"
    end

    local data_sync = skynet.address(".data_sync")
    for _, row_key in ipairs(row_keys) do
        if row_cache.exists(row_key) then
            local ok = skynet.call(data_sync, "lua", "flush_row", row_key)
            if not ok then
                logger.error(
                    "data_access.evict_player_cache flush failed, server_id=%s, act_id=%s, row_key=%s",
                    server_id, act_id, row_key
                )
                return "flush_failed"
            end
        end
    end

    for _, row_key in ipairs(row_keys) do
        if row_cache.exists(row_key) then
            row_cache.del_row(row_key)
        end
    end
    M.remove_last_login(server_id, act_id)
    logger.info("data_access.evict_player_cache ok, server_id=%s, act_id=%s", server_id, act_id)
    return "ok"
end
--]]
return M
