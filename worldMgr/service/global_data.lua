local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local DBDef = require "common.db_keys_define"

local CMD = {}

local ROLE_SHARD_EXPAND = DBDef.roleShardExpand

local _role_table_index = DBDef.tableIndexBase

local _GLOBAL_TIME = {
                        serverStartTime = 0, 
                        today0amUpdateTime = 0, 
                        today6amUpdateTime = 0
                    }
-- {serverStartTime, today0amUpdateTime, today6amUpdateTime}

local function get_global_time()
    local tt = {}
    local t = os.date("*t")
    t.hour = 0
	t.min = 0
	t.sec = 0
    tt.today0am = os.time(t)
    tt.tomorrow0am = tt.today0am + 86400
    t.hour = 6
    tt.today6am = os.time(t)
    tt.tomorrow6am = tt.today6am + 86400
    return tt
end

local function onToday0am()
    logger.info("onToday0am")

    _GLOBAL_TIME.today0amUpdateTime = os.time()
    skynet.call(".db_global", "lua", "update", "game_global", "idx", 1,
                {
                    last_0am_update = _GLOBAL_TIME.today0amUpdateTime
                }
            )

    -- 给旗下所有的world进程发送消息，通知其进行0点更新
    skynet.call(skynet.address(".handle_message"), "lua", "notify_world_0am_update")
end

local function onToday6am()
    logger.info("onToday6am")

    _GLOBAL_TIME.today6amUpdateTime = os.time()
    skynet.call(".db_global", "lua", "update", "game_global", "idx", 1,
                {
                    last_6am_update = _GLOBAL_TIME.today6amUpdateTime
                }
            )
    
    -- 给旗下所有的world进程发送消息，通知其进行6点更新
    skynet.call(skynet.address(".handle_message"), "lua", "notify_world_6am_update")
end

local function create_shard_table(base_name, suffix, auto_inc)
    local new_table = string.format("%s_%s", base_name, suffix)
    local base_table = string.format("%s_%s", base_name, DBDef.tableIndexBase)
    local ret = skynet.call(".db_game", "lua", "create_table", new_table, base_table)
    if ret and auto_inc then
        skynet.call(".db_game", "lua", "execute",
            string.format("ALTER TABLE `%s` AUTO_INCREMENT = %d", new_table, auto_inc))
    end
    return ret
end

local function ensure_bag_shards(max_dbid)
    if not max_dbid or max_dbid < DBDef.dbidBase then
        return
    end
    local bag_def = DBDef.Table.role.bag_slots
    local max_suffix = DBDef.calc_table_suffix(bag_def, max_dbid)
    for i = DBDef.tableIndexBase, max_suffix do
        create_shard_table("bag_slots", i, nil)
    end
end

local function check_role_shard_expand()
    local idx = _role_table_index
    local table_name = string.format("%s_%s", ROLE_SHARD_EXPAND.primary, idx)
    local ret, rs = skynet.call(".db_game", "lua", "execute",
        string.format("SELECT MAX(`dbid`) AS `max_dbid` FROM `%s`", table_name))
    local max_dbid = 0
    if ret and rs and rs[1] then
        max_dbid = tonumber(rs[1].max_dbid) or 0
    end

    ensure_bag_shards(max_dbid)

    local limit_dbid = DBDef.dbidBase + idx * ROLE_SHARD_EXPAND.sharding - ROLE_SHARD_EXPAND.expandThreshold
    if max_dbid < limit_dbid then
        return
    end

    local new_idx = idx + 1
    local auto_inc = DBDef.dbidBase + idx * ROLE_SHARD_EXPAND.sharding
    for _, name in ipairs(ROLE_SHARD_EXPAND.tables) do
        create_shard_table(name, new_idx, name == ROLE_SHARD_EXPAND.primary and auto_inc or nil)
    end

    _role_table_index = new_idx
    skynet.call(".db_global", "lua", "update", "game_global", "idx", 1, {
        role_table_index = new_idx,
    })
    logger.info("role shard expanded, new_index=%s, auto_inc=%s", new_idx, auto_inc)
end

local function start_shard_monitor()
    skynet.fork(function()
        while true do
            skynet.sleep(100 * 60 * 10)
            local ok, err = pcall(check_role_shard_expand)
            if not ok then
                logger.error("check_role_shard_expand failed, err=%s", tostring(err))
            end
        end
    end)
end

function CMD.get_role_table_index()
    return _role_table_index
end

local function get_global_data()
    logger.info("get_global_data")
	local ret, global_data = skynet.call(
                                        ".db_global", 
                                        "lua", 
                                        "select_all",
                                        "game_global"
                                    )
    logger.info("global_data: ret=%s, global_data=%s", ret, util.serialize(global_data))
    if not ret then
        return nil
    end
    
    local tt = get_global_time()
    if global_data and next(global_data) then
        global_data = global_data[1]
        _GLOBAL_TIME.last_0am_update = global_data.last_0am_update
        _GLOBAL_TIME.last_6am_update = global_data.last_6am_update
        _GLOBAL_TIME.server_start_time = global_data.server_start_time
        local idx = tonumber(global_data.role_table_index)
        if idx and idx >= DBDef.tableIndexBase then
            _role_table_index = idx
        end
    else    
        _GLOBAL_TIME.server_start_time = tt.today0am
        skynet.call(".db_global", "lua", "insert", "game_global", 
                    {
                        last_0am_update = 0, 
                        last_6am_update = 0, 
                        server_start_time = _GLOBAL_TIME.server_start_time,
                        role_table_index = DBDef.tableIndexBase,
                    }
                )
    end

    -- 若当前服务器启动时间超过凌晨0点且最后的0点更新时间不是今天则执行一次0点更新
    if _GLOBAL_TIME.serverStartTime > tt.today0am 
        and _GLOBAL_TIME.today0amUpdateTime < tt.today0am then
        onToday0am()
    end

    -- 若当前服务器启动时间超过凌晨6点且最后的6点更新时间不是今天则执行一次6点更新
    if _GLOBAL_TIME.serverStartTime > tt.today6am 
        and _GLOBAL_TIME.today6amUpdateTime < tt.today6am then
        onToday6am()
    end

    logger.info("global_data: last_0am_update=%s, last_6am_update=%s, server_start_time=%s", 
                _GLOBAL_TIME.last_0am_update, _GLOBAL_TIME.last_6am_update, _GLOBAL_TIME.server_start_time)
end


local function start_timer()
    local tt = get_global_time()
    local sleep_time1 = (tt.tomorrow0am - os.time()) * 100
    skynet.fork(function()
        while true do
            skynet.sleep(sleep_time1)
            onToday0am()
            tt = get_global_time()
            sleep_time1 = (tt.tomorrow0am - os.time()) * 100
        end
    end)
    local sleep_time2 = (tt.tomorrow6am - os.time()) * 100
    skynet.fork(function()
        while true do
            skynet.sleep(sleep_time2)
            onToday6am()
            tt = get_global_time()
            sleep_time2 = (tt.tomorrow6am - os.time()) * 100
        end
    end)
    logger.info("start_timer, sleep_time1=%s, sleep_time2=%s", sleep_time1, sleep_time2)
end


skynet.start(function()
	skynet.dispatch("lua", function(session, _, cmd, ...)
		snutil.lua_docmd(session, CMD, cmd, ...)
	end)

    get_global_data()
    pcall(check_role_shard_expand)

    start_timer()
    start_shard_monitor()

	skynet.register(".global_data")
	logger.info("worldMgr global_data started")
end)
