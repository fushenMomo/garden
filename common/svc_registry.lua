local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"

local _REGISTRY = {}
local CMD = {}

function CMD.register(name, address)
    assert(type(name) == "string" and name ~= "", "invalid service name")
    address = address or skynet.self()
    _REGISTRY[name] = address
    return true
end

function CMD.unregister(name)
    _REGISTRY[name] = nil
    return true
end

function CMD.query(name)
    return _REGISTRY[name]
end

function CMD.list()
    local ret = {}
    for name, address in pairs(_REGISTRY) do
        ret[name] = address
    end
    return ret
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, cmd, ...)
        local f = CMD[cmd]
        assert(f, string.format("unknown cmd: %s", tostring(cmd)))
        skynet.retpack(f(...))
    end)

    -- 是的，这个 register 调用是把当前服务注册为 ".svc_registry"，
    -- 供本 skynet 进程内其他服务通过名字查找和调用
    skynet.register(".svc_registry")
    logger.info("service registry started")
end)
