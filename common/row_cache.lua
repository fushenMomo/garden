local skynet = require "skynet"
require "skynet.manager"
local const = require "common.const"
local DBDef = require "common.db_keys_define"
local util = require "common.util"
local logger = require "common.logger"

local M = {}

local function redis_addr()
    -- skynet.localname(".redis") 返回注册名为“.redis”的服务的地址（handle）
    -- skynet.localname 可用于查询本地已注册的服务名对应的地址(handle)，仅限本节点；
    -- skynet.address(".redis") 也可以获取服务地址，但会做更多的名字解析，支持全局唯一名，可能触发 cluster 等操作，耗费资源更多；
    -- 一般在已知是本地唯一名时，优先用 localname，速度更快。
    return skynet.localname(".redis")
end

function M.encode_row(table_def, row)
    local fields = {}
    for i, db_field in ipairs(table_def.field) do
        local logic_field = DBDef.logic_field(table_def, db_field)
        local value = row[logic_field]
        if value ~= nil then
            local dtype = table_def.dataType[i]
            if dtype == DBDef.DataType.table or dtype == DBDef.DataType.json then
                fields[logic_field] = util.serialize(value)
            else
                fields[logic_field] = tostring(value)
            end
        end
    end
    return fields
end

function M.decode_row(table_def, raw)
    if not raw or not next(raw) then
        return nil
    end
    local row = {}
    for i, db_field in ipairs(table_def.field) do
        local logic_field = DBDef.logic_field(table_def, db_field)
        local value = raw[logic_field]
        if value ~= nil then
            local dtype = table_def.dataType[i]
            if dtype == DBDef.DataType.number then
                row[logic_field] = tonumber(value)
            elseif dtype == DBDef.DataType.table or dtype == DBDef.DataType.json then
                row[logic_field] = util.unserialize(value)
            else
                row[logic_field] = value
            end
        end
    end
    return row
end

function M.exists(row_key)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local ret = skynet.call(addr, "lua", "exists", row_key)
    return ret and ret == 1
end

function M.get_row(table_def, row_key)
    local addr = redis_addr()
    if not addr then
        return nil
    end
    local raw = skynet.call(addr, "lua", "hgetall", row_key)
    return M.decode_row(table_def, raw)
end

function M.set_row(table_def, row_key, row, ttl)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local fields = M.encode_row(table_def, row)
    if not next(fields) then
        return false
    end
    logger.info("row_cache.set_row, table_def=%s, row_key=%s, row=%s", table_def.tableName, row_key, util.serialize(row))
    skynet.call(addr, "lua", "hmset", row_key, fields)
    ttl = ttl or const.cache_ttl.timeout
    if ttl > 0 then
        skynet.call(addr, "lua", "expire", row_key, ttl)
    end
    return true
end

function M.del_row(row_key)
    local addr = redis_addr()
    if not addr then
        return false
    end
    skynet.call(addr, "lua", "del", row_key)
    return true
end

--@row_key
--@cached
--@changed_fields
function M.mark_dirty(row_key, cached, changed_fields)
    logger.info("row_cache.mark_dirty, row_key=%s, cached=%s", row_key, util.serialize(cached))
    local addr = redis_addr()
    if not addr then
        return false
    end

    if (not cached) or not next(cached) then
        return false
    end

    local data = util.serialize({row_key = row_key, cached = cached, changed_fields = changed_fields})
    skynet.call(addr, "lua", "lpush", const.redis_key.dirty_queue, data)

    return true
end


function M.get_dirty_queue_len()
    local addr = redis_addr()
    if not addr then
        return 0
    end
    return skynet.call(addr, "lua", "llen", const.redis_key.dirty_queue)
end

function M.pop_dirty_row_key()
    local addr = redis_addr()
    if not addr then
        return nil
    end
    return skynet.call(addr, "lua", "rpop", const.redis_key.dirty_queue)
end

function M.get_dirty_fields(row_key)
    local addr = redis_addr()
    if not addr then
        return nil
    end
    local fields_key = string.format(const.redis_key.dirty_fields, row_key)
    return skynet.call(addr, "lua", "smembers", fields_key)
end

function M.clear_dirty(row_key)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local fields_key = string.format(const.redis_key.dirty_fields, row_key)
    skynet.call(addr, "lua", "del", fields_key)
    return true
end

function M.try_lock(row_key, ttl)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local lock_key = string.format(const.redis_key.flush_lock, row_key)
    local ok = skynet.call(addr, "lua", "setNx", lock_key, "1")
    if ok then
        skynet.call(addr, "lua", "expire", lock_key, ttl or 30)
        return true
    end
    return false
end

function M.unlock(row_key)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local lock_key = string.format(const.redis_key.flush_lock, row_key)
    skynet.call(addr, "lua", "del", lock_key)
    return true
end

return M
