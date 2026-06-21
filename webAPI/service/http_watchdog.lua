local skynet = require "skynet"
local socket = require "skynet.socket"
local logger = require "common.logger"

local CMD = {}

function CMD.start(conf)
	local agent = {}
	local protocol = conf.protocol or "http"
	local agent_count = conf.agent_count or 8
	for i = 1, agent_count do
		agent[i] = skynet.newservice("service/http_agent", "agent", protocol)
	end
	local balance = 1
	local id = socket.listen(conf.address, conf.port)
	logger.info("http_watchdog listen %s:%s protocol=%s", conf.address, conf.port, protocol)
	socket.start(id, function(fd, addr)
		skynet.send(agent[balance], "lua", fd, addr)
		balance = balance + 1
		if balance > #agent then
			balance = 1
		end
	end)
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, cmd, ...)
		local f = CMD[cmd]
		if f then
			f(...)
		end
	end)
end)
