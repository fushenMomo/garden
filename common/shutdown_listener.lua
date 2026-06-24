local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local graceful_stop = require "common.graceful_stop"

skynet.register_protocol {
    name = "SYSTEM",
    id = skynet.PTYPE_SYSTEM,
    unpack = function() end,
    dispatch = function()
        logger.info("shutdown_listener recv USR1")
        pcall(skynet.call, ".handle_message", "lua", "graceful_stop")
    end,
}

skynet.start(function()
    skynet.register(".shutdown_listener")
    logger.info("shutdown_listener started")
end)
