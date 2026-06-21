-- ============================= 涉及skynet 的辅助函数 ===========================

local skynet = require "skynet"
local logger = require "common.logger"
local M = {}

function M.handle_err(e)
    e = debug.traceback(coroutine.running(), tostring(e), 2)
    -- xpcall 的错误处理函数中不能调用会 yield 的接口（如 logger.info -> skynet.call）
    skynet.error(e)
    return e
end

function M.lua_docmd(session, handler, cmd, ...)
    cmd = string.lower(cmd)
    local f = handler[cmd]
    if not f then
        error(string.format("%s unknown cmd: %s", SERVICE_NAME, cmd))
    end
    if session == 0 then
        -- 0 = 无需回复
        return f(...)
    else
        -- 非0 = 需要回复
        return skynet.ret(skynet.pack(f(...)))
    end
end

return M