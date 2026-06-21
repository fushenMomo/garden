local logger = require "common.logger"

local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil

local player = nil

M.REQUEST = REQUEST
M.CMD = CMD

--@global
function M.init(global)
    logger.info("friend init")
    _GLOBAL = global
    player = require "world.service.agent.player"
end

function M.load_data()
    logger.info("friend load_data")

end

function M.tick()
    --logger.info("friend tick")
end

function M.load_complete()
    logger.info("friend load_complete")

end

function M.sync_data()
    logger.info("friend sync_data")

end

function M.onToday0am()
    logger.info("friend onToday0am")
end

function M.onToday6am()
    logger.info("friend onToday6am")
end

function M.close()
    logger.info("friend close")
    
end



return M