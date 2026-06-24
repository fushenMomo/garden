local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local graceful_stop = require "common.graceful_stop"

local CMD = {}

-- proc_id -> { load_value = number, over_load = bool, sync_time = seconds }
local _WORLD_LOADING = {}
local _CUR_BEST_WORLD_PROC_ID = nil
local _SERVER_ID = nil
--local _WORLD_FUNC_MAP = {}

-- 按负载挑选可用 world 进程，优先不过载且在线人数最少
local function pick_world_proc()
	local server_load = _WORLD_LOADING

	local best_proc_id = nil
	local best_info = nil
	for proc_id, info in pairs(server_load) do
		if info and (not info.over_load) then
			if (not best_info) or (info.load_value < best_info.load_value) then
				best_proc_id = proc_id
				best_info = info
			end
		end
	end

	if not best_proc_id then
		return nil
	end
	return best_proc_id, best_info
end

-- world 节点上报当前负载信息
--@proc_id
--@load_value
--@over_load
function CMD.sync_world_loading(proc_id, load_value, over_load)
    logger.info("sync_world_loading received, proc_id=%s load_value=%s over_load=%s",
                proc_id, load_value, over_load)
	proc_id = tonumber(proc_id)
	load_value = tonumber(load_value)
	
    if not _WORLD_LOADING[proc_id] then
        _WORLD_LOADING[proc_id] = {}
    end

    -- 基础数据信息
    _WORLD_LOADING[proc_id].load_value = load_value
    _WORLD_LOADING[proc_id].over_load = over_load
    _WORLD_LOADING[proc_id].sync_time = skynet.time()

    local best_proc_id = pick_world_proc()
    if (not _CUR_BEST_WORLD_PROC_ID) or (_CUR_BEST_WORLD_PROC_ID ~= best_proc_id) then
        _CUR_BEST_WORLD_PROC_ID = best_proc_id
        logger.info("sync_world_loading, best_proc_id=%s", best_proc_id)
		local gateway_count = tonumber(skynet.getenv("gateway_count"))
		for idx = 1, gateway_count do
			local dest_cluster_name = "gateway" .. "_" .. skynet.getenv("server_id") .. "_" .. idx
			cluster.send(
							dest_cluster_name, 
							".handle_message", 
							"sync_cur_open_world_proc", 
							best_proc_id
						)
		end
    end

	return true
end


function CMD.notify_world_0am_update()
    logger.info("notify_world_0am_update")

	for proc_id, _ in pairs(_WORLD_LOADING) do
		cluster.send(
							"world_" .. _SERVER_ID .. "_" .. proc_id,
							".handle_message", 
							"notify_world_0am_update"
						)
	end

	local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		cluster.send(
							"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
							".guild_manager", 
							"notify_world_0am_update"
						)
	end
    return true
end


function CMD.notify_world_6am_update()		
    logger.info("notify_world_6am_update")

	for proc_id, _ in pairs(_WORLD_LOADING) do
		cluster.send(
							"world_" .. _SERVER_ID .. "_" .. proc_id,
							".handle_message", 
							"notify_world_6am_update"
						)
	end

	local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		cluster.send(
							"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
							".guild_manager", 
							"notify_world_6am_update"
						)
	end
    
    return true
end


function CMD.login_guild(msg)
    logger.info("login_guild received, msg=%s", util.serialize(msg))
    local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		local ret = cluster.call(
							"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
							".guild_manager", 
							"login_guild", 
							msg
						)
		return ret
	end
	return false
end

function CMD.logout_guild(msg)
    logger.info("logout_guild received, msg=%s", util.serialize(msg))
    local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		local ret = cluster.call(
							"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
							".guild_manager", 
							"logout_guild", 
							msg
						)
		return ret
	end
	return false
end

function CMD.change_guild_desc(msg)
    logger.info("change_guild_desc received, msg=%s", util.serialize(msg))
    local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		local ret = cluster.call(
								"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
								".guild_manager", 
								"change_guild_desc", 
								msg
							)
		return ret
	end
	return false
end


function CMD.create_guild(msg)
    logger.info("create_guild received, msg=%s", util.serialize(msg))
    local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		local ret, guild_id = cluster.call(
								"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
								".guild_manager", 
								"create_guild", 
								msg
							)
		return ret, guild_id
	end
	return false
end


function CMD.get_guild_info(msg)
    logger.info("get_guild_info received, msg=%s", util.serialize(msg))
	local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		local ret, msg = cluster.call(
								"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
								".guild_manager", 
								"get_guild_info", 
								msg
							)
		return ret, msg
	end
	return false
end

function CMD.get_guild_list()
    logger.info("get_guild_list received")
	local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		local ret, msg = cluster.call(
								"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
								".guild_manager", 
								"get_guild_list"
							)
		return ret, msg
	end
	return false
end


function CMD.join_guild(msg)
    logger.info("join_guild received, msg=%s", util.serialize(msg))
	local guild_world_proc_id = skynet.getenv("GUILD_WORLD_PROC_ID")
	if guild_world_proc_id then
		local ret = cluster.call(
								"world_" .. _SERVER_ID .. "_" .. guild_world_proc_id,
								".guild_manager", 
								"join_guild", 
								msg
							)
		return ret
	end
	return false
end


function CMD.web_kick_player(acc_id)
    logger.info("web_kick_player received, acc_id=%s", acc_id)
	return true
end

function CMD.web_ban_player(acc_id, reason)
    logger.info("web_ban_player received, acc_id=%s reason=%s", acc_id, reason)
	return true
end

--[[
--@proc_id
--@world_func_flag
function CMD.register_world_func(proc_id, world_func_flag)
	if not _WORLD_FUNC_MAP[proc_id] then
		_WORLD_FUNC_MAP[proc_id] = {}
	end
	_WORLD_FUNC_MAP[proc_id].func_flag = world_func_flag
	return true
end
--]]

function CMD.debug_dump()
	return util.serialize(_WORLD_LOADING)
end

function CMD.graceful_stop()
    logger.info("worldMgr graceful_stop begin")
    local data_sync = skynet.localname(".data_sync")
    if data_sync then
        pcall(skynet.call, data_sync, "lua", "flush_all")
    end
    return graceful_stop.finish()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)

	_SERVER_ID = skynet.getenv("server_id")

	skynet.register(".handle_message")
	logger.info("worldMgr handle_message started")
end)
