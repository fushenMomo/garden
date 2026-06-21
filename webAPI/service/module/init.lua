local system = require "webAPI.service.module.system"
local player = require "webAPI.service.module.player"
local guild = require "webAPI.service.module.guild"

local M = {
	_modules = {},
}

function M.register(name, mod)
	M._modules[name] = mod
end

function M.get(name)
	return M._modules[name]
end

M.register("system", system)
M.register("player", player)
M.register("guild", guild)

return M
