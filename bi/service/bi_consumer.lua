local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local bi_queue = require "common.bi_queue"
local file_log = require "bi.service.handlers.file_log"
local server_traceback = require "bi.service.handlers.server_traceback"

local POLL_INTERVAL = 100
local MAX_BATCH = 100

local function process_one(entry_raw)
    local entry = util.unserialize(entry_raw)
    if not entry then
        logger.error("bi_consumer invalid entry")
        return false
    end
    local ok, err
    if entry.data and entry.data.event == "server_traceback" then
        ok, err = server_traceback.handle(entry)
    else
        ok, err = file_log.handle(entry)
    end
    if not ok then
        logger.error("bi_consumer handle failed, err=%s", tostring(err))
        return false
    end
    return true
end

local function backup()
    local server_id = tonumber(skynet.getenv("server_id"))
    if not server_id then
        return
    end
    local nlen = bi_queue.len(server_id)
    if nlen <= 0 then
        return
    end
    if nlen > MAX_BATCH then
        nlen = MAX_BATCH
    end
    local count = 0
    local element = bi_queue.pop(server_id)
    while element do
        process_one(element)
        count = count + 1
        if count >= nlen then
            break
        end
        element = bi_queue.pop(server_id)
    end
end

local function poll_loop()
    while true do
        backup()
        skynet.sleep(POLL_INTERVAL)
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, {}, cmd, ...)
    end)
    skynet.fork(poll_loop)
    skynet.register(".bi_consumer")
    logger.info("bi_consumer service started")
end)
