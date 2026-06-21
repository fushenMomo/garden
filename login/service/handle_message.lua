local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"

local CMD = {}

local _SERVERMGR_SYNC_INFO = {}


local function get_servermgr_cluster_name(server_id)
	return "serverMgr_" .. (server_id or 1) .. "_1"
end



skynet.start(function()
	skynet.dispatch("lua", function(session, _, cmd, ...)
		snutil.lua_docmd(session, CMD, cmd, ...)
	end)

	skynet.register(".handle_message")
	logger.info("login handle_message started")
end)
