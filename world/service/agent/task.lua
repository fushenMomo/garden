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
    logger.info("task init")
    _GLOBAL = global
    player = require "world.service.agent.player"
end

function M.load_data()
    logger.info("task load_data")

end

function M.tick()
    --logger.info("task tick")
end

function M.load_complete()
    logger.info("task load_complete")

end

function M.sync_data()
    logger.info("task sync_data")

end

function M.onToday0am()
    logger.info("task onToday0am")
end

function M.onToday6am()
    logger.info("task onToday6am")
end

function M.close()
    logger.info("task close")
    
end



return M