local skynet = require "skynet"
require "skynet.manager"

local cluster = require "skynet.cluster"
local logger = require "common.logger"
--local debug_console = require "common.debug_console_ex"

skynet.start(function()
	logger.init({base_dir = "../log/webAPI"})
	logger.info("business logger initialized")

	skynet.uniqueservice("config_mgr")
	skynet.uniqueservice("service/handle_message")

	local nodename = skynet.getenv("nodename") or "webAPI"
	cluster.open(nodename)

	local port = tonumber(skynet.getenv("http_port")) or 8900
	local protocol = skynet.getenv("http_protocol") or "http"
	local agent_count = tonumber(skynet.getenv("http_agent_count")) or 8

	local watchdog = skynet.newservice("service/http_watchdog")
	skynet.call(watchdog, "lua", "start", {
		address = "0.0.0.0",
		port = port,
		protocol = protocol,
		agent_count = agent_count,
	})

	--debug_console.start()
	skynet.register(".webAPI_main")
	logger.info("webAPI server started, port=%s protocol=%s", port, protocol)
end)
