local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local graceful_stop = require "common.graceful_stop"
local modules = require "webAPI.service.module.init"

local CMD = {}

function CMD.web_notify(module, action, data)
	logger.info("web_notify module=%s action=%s", tostring(module), tostring(action))
	local mod = modules.get(module)
	if not mod or not mod.on_notify then
		logger.error("web_notify module not found, module=%s", tostring(module))
		return false
	end
	return mod.on_notify(action, data)
end

function CMD.call_servermgr(cmd, ...)
	local ok, ret = pcall(cluster.call, "serverMgr", ".handle_message", cmd, ...)
	if not ok then
		logger.error("call_servermgr failed, cmd=%s err=%s", tostring(cmd), tostring(ret))
		return nil
	end
	return ret
end

function CMD.call_worldmgr(server_id, cmd, ...)
	server_id = tonumber(server_id) or 1
	local node = string.format("worldMgr_%s_1", server_id)
	local ok, ret = pcall(cluster.call, node, ".handle_message", cmd, ...)
	if not ok then
		logger.error("call_worldmgr failed, node=%s cmd=%s err=%s", node, tostring(cmd), tostring(ret))
		return nil
	end
	return ret
end

function CMD.call_world(server_id, proc_id, cmd, ...)
	server_id = tonumber(server_id) or 1
	proc_id = tonumber(proc_id) or 1
	local node = string.format("world_%s_%s", server_id, proc_id)
	local ok, ret = pcall(cluster.call, node, ".handle_message", cmd, ...)
	if not ok then
		logger.error("call_world failed, node=%s cmd=%s err=%s", node, tostring(cmd), tostring(ret))
		return nil
	end
	return ret
end

function CMD.get_proc_state(group_id)
	local ok, ret = pcall(cluster.call, "serverMgr", ".proc_state_service", "query", group_id)
	if not ok then
		logger.error("get_proc_state failed, group_id=%s err=%s", tostring(group_id), tostring(ret))
		return nil
	end
	return ret
end

function CMD.graceful_stop()
	logger.info("webAPI graceful_stop begin")
	return graceful_stop.finish()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)
	skynet.register(".handle_message")
	logger.info("webAPI handle_message started")
end)
