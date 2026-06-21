local skynet = require "skynet"
local logger = require "common.logger"

local M = {}

function M.start()
	local port = tonumber(skynet.getenv("debug_console"))
	logger.info("debug_console_ex_start port: %s", tostring(port))	
	if port and port > 0 then
		local addr = skynet.newservice("debug_console", "0.0.0.0", port)
		assert(addr, "debug_console start failed")
		logger.info("debug_console_ex listening on 0.0.0.0:%s", tostring(port))
	else
		logger.info("debug_console_ex start skipped: missing debug_console config")
	end
end

return M
