local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local graceful_stop = require "common.graceful_stop"

local CMD = {}

local _LOGIN_SYNC_INFO = {}
local _WORLDMGR_SYNC_INFO = {}


local function get_worldmgr_cluster_name(server_id)
	return "worldMgr_" .. server_id .. "_1"
end


local function notify_login_online()
	local ok, err = pcall(function()
		cluster.send("login", ".handle_message", "sync_from_servermgr", {
			event = "servermgr_online",
			time = skynet.time(),
		})
	end)
	if not ok then
		logger.error("notify_login_online failed, err=%s", tostring(err))
	end
end


local function notify_worldmgr_online(server_id)
	local ok, err = pcall(function()
		cluster.send(get_worldmgr_cluster_name(server_id), ".handle_message", "sync_from_servermgr", {
			event = "servermgr_online",
			server_id = server_id,
			time = skynet.time(),
		})
	end)
	if not ok then
		logger.error("notify_worldmgr_online failed, err=%s", tostring(err))
	end
end


function CMD.sync_from_login(msg)
	logger.info("sync_from_login received, msg=%s", util.serialize(msg))
	_LOGIN_SYNC_INFO = msg or {}
	_LOGIN_SYNC_INFO.sync_time = skynet.time()
	return true
end


function CMD.sync_from_worldmgr(msg)
	logger.info("sync_from_worldmgr received, msg=%s", util.serialize(msg))
	_WORLDMGR_SYNC_INFO = msg or {}
	_WORLDMGR_SYNC_INFO.sync_time = skynet.time()
	return true
end


function CMD.fetch_worldmgr_loading(server_id)
	server_id = tonumber(server_id)
	if not server_id then
		return nil
	end
	local ok, ret = pcall(function()
		return cluster.call(get_worldmgr_cluster_name(server_id), ".handle_message", "debug_dump")
	end)
	if not ok then
		logger.error("fetch_worldmgr_loading failed, err=%s", tostring(ret))
		return nil
	end
	return ret
end


function CMD.debug_dump()
	return util.serialize({
		login_sync = _LOGIN_SYNC_INFO,
		worldmgr_sync = _WORLDMGR_SYNC_INFO,
	})
end

function CMD.graceful_stop()
	logger.info("serverMgr graceful_stop begin")
	return graceful_stop.finish()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)

	skynet.register(".handle_message")
	logger.info("serverMgr handle_message started")

end)
