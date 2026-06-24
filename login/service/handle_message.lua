local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local graceful_stop = require "common.graceful_stop"

local CMD = {}

function CMD.graceful_stop()
	logger.info("login graceful_stop begin")
	return graceful_stop.finish()
end

local _SERVERMGR_SYNC_INFO = {}


local function get_servermgr_cluster_name()
	return "serverMgr"
end



skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)

	skynet.register(".handle_message")
	logger.info("login handle_message started")
end)
