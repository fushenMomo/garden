local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
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
	local ok, ret = pcall(cluster.call, "serverMgr_1_1", ".handle_message", cmd, ...)
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

skynet.start(function()
	skynet.dispatch("lua", function(session, _, cmd, ...)
		snutil.lua_docmd(session, CMD, cmd, ...)
	end)
	skynet.register(".handle_message")
	logger.info("webAPI handle_message started")
end)
