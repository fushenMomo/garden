local skynet = require "skynet"
local proc_state = require "common.proc_state"
local logger = require "common.logger"

local M = {}

local _stopping = false

function M.start_listener()
    local svc = skynet.uniqueservice("shutdown_listener")
    skynet.name(".shutdown_listener", svc)
end

function M.finish(hooks)
    if _stopping then
        return true
    end
    _stopping = true
    if type(hooks) == "table" then
        for _, fn in ipairs(hooks) do
            local ok, err = pcall(fn)
            if not ok then
                logger.error("graceful_stop hook failed, err=%s", tostring(err))
            end
        end
    end
    proc_state.closed()
    skynet.fork(function()
        skynet.sleep(50)
        skynet.abort()
    end)
    return true
end

return M
