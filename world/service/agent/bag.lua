local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local data_access = require "common.data_access"

local const = require "common.const"

local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil

local _BAG_SLOTS = nil
local player = nil

M.REQUEST = REQUEST
M.CMD = CMD

--@global
function M.init(global)
    logger.info("player init")
    _GLOBAL = global
    player = require "world.service.agent.player"
end

local function init_default_slots()
    _BAG_SLOTS = data_access.load_many("bag_slots", { parentDBID = player.get_role_base_dbid() })
    -- [20260610 15:16:26] [INFO] [addr__00000013] bag load_data success, slots={{data={},index=1,itemID=10001,guid2=0,parentDBID=10518,guid1=0,count=10,},}
    logger.info("bag load_data success1, _BAG_SLOTS=%s", util.serialize(_BAG_SLOTS))


    local default_count = const.bag_slots.default_count
    local count = #_BAG_SLOTS
    if count < default_count then
        for i = count + 1, default_count do
            local slot = {
                parentDBID = player.get_role_base_dbid(),
                index = i,
                guid1 = player.get_role_base_dbid(), guid2 = 0, itemID = 0, count = 0, data = {}
            }

            local ret = data_access.insert("bag_slots", slot)
            if ret then
                table.insert(_BAG_SLOTS, slot)
            end
        end
    end
end

function M.load_data()
    logger.info("bag load_data")
    init_default_slots()

    --[[
    if _BAG_SLOTS[1] then
        _BAG_SLOTS[1].count = 1
        _BAG_SLOTS[1].guid1 = player and player.get_role_base_dbid()
        data_access.save("bag_slots", _BAG_SLOTS[1])
        logger.info("bag load_data success2, _BAG_SLOTS=%s", util.serialize(_BAG_SLOTS))
    end

    -- 新增格子（先写 MySQL，再写缓存）
    local ret, insert_id = data_access.insert("bag_slots", {
        parentDBID = player.get_role_base_dbid(),
        index = 2,
        guid1 = 0,
        guid2 = 0,
        itemID = 10002,
        count = 1,
        data = {x=1,y=2,z=3},
    })
    if not ret then
        logger.error("bag load_data failed, insert_id=%s", insert_id)
        return
    end
    logger.info("bag load_data success3, insert_id=%s", insert_id)
    --_BAG_SLOTS = data_access.load_many("bag_slots", { parentDBID = player.get_role_base_dbid() })
    --logger.info("bag load_data success3, _BAG_SLOTS=%s", util.serialize(_BAG_SLOTS))
    --]]
end

function M.load_complete()
    logger.info("bag load_complete")

end

function M.tick()
    --logger.info("bag tick")
end

function M.sync_data()
    logger.info("bag sync_data")

end

function M.onToday0am()
    logger.info("bag onToday0am")
end

function M.onToday6am()
    logger.info("bag onToday6am")
end

function M.close()
    logger.info("bag close")
    
end



return M