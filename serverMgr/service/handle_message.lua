local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"

local CMD = {}

local _SERVER_ID = nil
local _LOGIN_SYNC_INFO = {}
local _WORLDMGR_SYNC_INFO = {}


local function get_worldmgr_cluster_name()
	return "worldMgr_" .. _SERVER_ID .. "_1"
end


local function notify_login_online()
	local ok, err = pcall(function()
		cluster.send("login", ".handle_message", "sync_from_servermgr", {
			event = "servermgr_online",
			server_id = _SERVER_ID,
			time = skynet.time(),
		})
	end)
	if not ok then
		logger.error("notify_login_online failed, err=%s", tostring(err))
	end
end


local function notify_worldmgr_online()
	local ok, err = pcall(function()
		cluster.send(get_worldmgr_cluster_name(), ".handle_message", "sync_from_servermgr", {
			event = "servermgr_online",
			server_id = _SERVER_ID,
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


function CMD.fetch_worldmgr_loading()
	local ok, ret = pcall(function()
		return cluster.call(get_worldmgr_cluster_name(), ".handle_message", "debug_dump")
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


skynet.start(function()
	skynet.dispatch("lua", function(session, _, cmd, ...)
		snutil.lua_docmd(session, CMD, cmd, ...)
	end)

	_SERVER_ID = tonumber(skynet.getenv("server_id"))
	skynet.register(".handle_message")
	logger.info("serverMgr handle_message started")

end)
