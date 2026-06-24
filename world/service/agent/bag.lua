local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local data_access = require "common.data_access"


local sharedata = require "skynet.sharedata"
local const = nil
local cfg_item = nil

local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil

local _BAG = nil
local _BAG_SLOTS = nil
local player = nil



M.REQUEST = REQUEST
M.CMD = CMD


--@global
function M.init(global)
    logger.info("player init")
    _GLOBAL = global
    player = require "world.service.agent.player"
    const = sharedata.query("const")
    cfg_item = sharedata.query("cfg_item")
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

local function load_bag()
    _BAG = data_access.load("bag", { parentDBID = player.get_role_base_dbid() })
    if not _BAG then
        local ok = data_access.insert("bag", { parentDBID = player.get_role_base_dbid(), itemList = {} })
        if not ok then
            return
        end
        _BAG = data_access.load("bag", { parentDBID = player.get_role_base_dbid() })
    end
    if _BAG and not _BAG.itemList then
        _BAG.itemList = {}
    end
end

function M.load_data()
    logger.info("bag load_data")
    load_bag()
    init_default_slots()
end

function M.load_complete()
    logger.info("bag load_complete")
end

function M.tick()
end

function M.sync_data()
    logger.info("bag sync_data")
    if not _BAG or not _BAG.itemList then
        return
    end

    local info_list = {}
    for item_id, item_count in pairs(_BAG.itemList) do
        table.insert(info_list, {
            item_id = item_id,
            item_count = item_count,
        })
    end
    _GLOBAL.push_client("update_bag_item_list", {
        info_list = info_list,
    })
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

function M.get_bag_data()
    return _BAG
end

function M.get_item_count(itemID)
    if not _BAG or not _BAG.itemList then
        return 0
    end
    return _BAG.itemList[itemID] or 0
end

function M.add_item(itemID, count)
    if not _BAG or not itemID or not count or count <= 0 then
        return false
    end
    _BAG.itemList = _BAG.itemList or {}
    _BAG.itemList[itemID] = (_BAG.itemList[itemID] or 0) + count
    data_access.save("bag", _BAG, {"itemList"})
    return true
end

function M.sub_item(itemID, count)
    if not _BAG or not itemID or not count or count <= 0 then
        return false
    end
    local cur = _BAG.itemList and _BAG.itemList[itemID] or 0
    if cur < count then
        return false
    end
    cur = cur - count
    if cur <= 0 then
        _BAG.itemList[itemID] = nil
    else
        _BAG.itemList[itemID] = cur
    end
    data_access.save("bag", _BAG, {"itemList"})
    return true
end

function REQUEST:gainItem()
    local item_id = tonumber(self.item_id)
    local item_count = tonumber(self.item_count)
    if not item_id or not item_count or item_count <= 0 then
        return {error_code = const.error_code.param_error}
    end

    logger.info("gainItem request, item_id=%s, item_count=%s", item_id, item_count)
    
    local item_cfg = cfg_item[item_id]
    if not item_cfg then
        return {error_code = const.error_code.item_not_found}
    end
    
    if item_cfg.type == const.item_type.weapon then
        return {error_code = const.error_code.param_error}
    end
    
    if not M.add_item(item_id, item_count) then
        return {error_code = const.error_code.add_item_failed}
    end

    _GLOBAL.push_client("update_bag_item_list", {
        info_list = {
            {
                item_id = item_id,
                item_count = M.get_item_count(item_id),
            },
        },
    })

    return {error_code = const.error_code.success}
end


function REQUEST:costItem()
    local item_id = self.item_id
    local item_count = self.item_count
    if not item_id or not item_count or item_count <= 0 then
        return {error_code = const.error_code.param_error}
    end
    
    local item_cfg = cfg_item[item_id]
    if not item_cfg then
        return {error_code = const.error_code.item_not_found}
    end
    
    if item_cfg.type == const.item_type.weapon then
        return {error_code = const.error_code.param_error}
    end
    
    if not M.sub_item(item_id, item_count) then
        return {error_code = const.error_code.sub_item_failed}
    end

    _GLOBAL.push_client("update_bag_item_list", {
        info_list = {
            {
                item_id = item_id,
                item_count = M.get_item_count(item_id),
            },
        },
    })

    return {error_code = const.error_code.success}
end

return M
