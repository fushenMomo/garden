local skynet = require "skynet"
local bi_log = require "common.bi_log"

local M = {}

function M.push(level, message)
    local server_id = tonumber(skynet.getenv("server_id"))
    if not server_id or not message or message == "" then
        return false
    end
    if skynet.getenv("nodename") == "bi" then
        skynet.error(string.format("[%s] %s", level, message))
        return false
    end
    pcall(bi_log.push, server_id, {
        event = "server_traceback",
        level = level,
        message = message,
    })
    return true
end

return M
