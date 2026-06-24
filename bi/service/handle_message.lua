local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local snutil = require "common.snutil"
local graceful_stop = require "common.graceful_stop"

local CMD = {}

function CMD.graceful_stop()
	logger.info("bi graceful_stop begin")
	return graceful_stop.finish()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)
	skynet.register(".handle_message")
	logger.info("bi handle_message started")
end)
