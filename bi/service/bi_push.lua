local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local snutil = require "common.snutil"
local bi_queue = require "common.bi_queue"

local CMD = {}

function CMD.push(entry)
    local server_id = tonumber(skynet.getenv("server_id"))
    if not server_id or not entry then
        return false
    end
    return bi_queue.push(server_id, entry)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, CMD, cmd, ...)
    end)
    skynet.register(".bi_push")
    logger.info("bi_push service started")
end)
