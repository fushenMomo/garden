local skynet = require "skynet"

local M = {}

M.handlers = {}

function M.handlers.ping(ctx)
	return {
		msg = "pong",
		time = skynet.time(),
		addr = ctx.addr,
	}
end

function M.handlers.health(ctx)
	return {
		msg = "ok",
		service = "webAPI",
		time = skynet.time(),
	}
end

return M
