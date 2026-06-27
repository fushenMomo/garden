local logger = require "common.logger"
local data_access = require "common.data_access"
local util = require "common.util"
local sharedata = require "skynet.sharedata"

local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil
local player = nil
local const = nil
local cfg_task = nil

local _TASK_LIST = nil
local _TASK_MAP = nil
local _MAX_TASK_INDEX = 0
local _ACCEPT_INDEX = nil
local _partner = nil

M.REQUEST = REQUEST
M.CMD = CMD

local function rebuild_accept_index()
    _ACCEPT_INDEX = {}
    for _, cfg in pairs(cfg_task or {}) do
        local accept_type = cfg.acceptType
        if accept_type then
            _ACCEPT_INDEX[accept_type] = _ACCEPT_INDEX[accept_type] or {}
            table.insert(_ACCEPT_INDEX[accept_type], cfg.taskID)
        end
    end
end

function M.init(global)
    _GLOBAL = global
    player = require "world.service.agent.player"
    _partner = require "world.service.agent.partner"
    const = sharedata.query("const")
    cfg_task = sharedata.query("cfg_task")
    rebuild_accept_index()
end

local function rebuild_task_map()
    _TASK_MAP = {}
    for _, row in ipairs(_TASK_LIST or {}) do
        _TASK_MAP[row.taskIndex] = row
        if row.taskIndex > _MAX_TASK_INDEX then
            _MAX_TASK_INDEX = row.taskIndex
        end
    end
end

local function next_task_index()
    _MAX_TASK_INDEX = _MAX_TASK_INDEX + 1
    return _MAX_TASK_INDEX
end

local function build_task_info(row)
    local data = row.data or {}
    return {
        task_index = row.taskIndex,
        task_id = row.taskID,
        status = row.status or const.task_status.going,
        time = row.time or 0,
        cur_value = data.curValue or 0,
        dest_value = data.destValue or 0,
    }
end

local function get_complete_cur_value(complete_type)
    if complete_type == const.task_complete_type.partner_count then
        return #(_partner.get_partner_list() or {})
    end
    return 0
end

local function check_task_complete(row, cfg)
    if row.status ~= const.task_status.going then
        return false
    end
    local cur_value = get_complete_cur_value(cfg.completeType)
    local dest_value = (cfg.completeParam and cfg.completeParam.count) or 0
    local fields = {
        data = {
            curValue = cur_value,
            destValue = dest_value,
        },
    }
    if cur_value >= dest_value then
        fields.status = const.task_status.completed
    end
    M.update_task(row.taskIndex, fields)
    return true, build_task_info(row)
end

function M.load_data()
    _TASK_LIST = data_access.load_many("task", { parentDBID = player.get_role_base_dbid() }) or {}
    rebuild_task_map()
    logger.info("task load_data success, count=%s", #_TASK_LIST)
end

function M.load_complete()
    M.on_accept_event(const.task_accept_type.login)
end

function M.tick()
end

function M.push_task_update(info_list)
    _GLOBAL.push_client("update_task_list", {
        info_list = info_list,
    })
end

function M.sync_data()
    local info_list = {}
    for _, row in ipairs(_TASK_LIST or {}) do
        table.insert(info_list, build_task_info(row))
    end
    M.push_task_update(info_list)
end

function M.onToday0am()
end

function M.onToday6am()
end

function M.close()
end

function M.get_task_list()
    return _TASK_LIST
end

function M.get_task(task_index)
    return _TASK_MAP and _TASK_MAP[task_index]
end

function M.get_task_by_id(task_id)
    for _, row in ipairs(_TASK_LIST or {}) do
        if row.taskID == task_id then
            return row
        end
    end
end

function M.add_task(task_id, data)
    if not task_id or task_id <= 0 then
        return false
    end
    if #(_TASK_LIST or {}) >= const.task.max_count then
        return false
    end
    local task_index = next_task_index()
    local row = {
        parentDBID = player.get_role_base_dbid(),
        taskIndex = task_index,
        taskID = task_id,
        data = data or {},
        status = const.task_status.going,
        time = os.time(),
    }
    local ok = data_access.insert("task", row)
    if not ok then
        return false
    end
    table.insert(_TASK_LIST, row)
    _TASK_MAP[task_index] = row
    return true, row
end

function M.update_task(task_index, fields)
    local row = _TASK_MAP and _TASK_MAP[task_index]
    if not row or not fields then
        return false
    end
    local changed_fields = {}
    for k, v in pairs(fields) do
        if row[k] ~= v then
            row[k] = v
            table.insert(changed_fields, k)
        end
    end
    if #changed_fields == 0 then
        return true
    end
    data_access.save("task", row, changed_fields)
    return true
end

function M.on_accept_event(accept_type)
    local task_ids = _ACCEPT_INDEX and _ACCEPT_INDEX[accept_type]
    if not task_ids then
        return
    end
    local update_list = {}
    for _, task_id in ipairs(task_ids) do
        if not M.get_task_by_id(task_id) then
            local cfg = cfg_task[task_id]
            if cfg then
                local dest_value = (cfg.completeParam and cfg.completeParam.count) or 0
                local ok, row = M.add_task(task_id, { curValue = 0, destValue = dest_value })
                if ok and row then
                    local _, info = check_task_complete(row, cfg)
                    if info then
                        table.insert(update_list, info)
                    end
                end
            end
        end
    end
    if #update_list > 0 then
        M.push_task_update(update_list)
    end
end

function M.on_complete_event(complete_type)
    local update_list = {}
    for _, row in ipairs(_TASK_LIST or {}) do
        if row.status == const.task_status.going then
            local cfg = cfg_task[row.taskID]
            if cfg and cfg.completeType == complete_type then
                local changed, info = check_task_complete(row, cfg)
                if changed and info then
                    table.insert(update_list, info)
                end
            end
        end
    end
    if #update_list > 0 then
        M.push_task_update(update_list)
    end
end

function REQUEST:receive_task_reward()
    local task_index = tonumber(self.task_index)
    if not task_index or task_index <= 0 then
        return { error_code = const.error_code.invalid_params }
    end
    local row = M.get_task(task_index)
    if not row then
        return { error_code = const.error_code.task_not_found }
    end
    if row.status == const.task_status.received then
        return { error_code = const.error_code.task_reward_received }
    end
    if row.status ~= const.task_status.completed then
        return { error_code = const.error_code.task_not_completed }
    end
    local cfg = cfg_task[row.taskID]
    if not cfg or not cfg.rewardList then
        return { error_code = const.error_code.invalid_params }
    end
    local bag = require "world.service.agent.bag"
    local bag_update_list = {}
    for _, reward in ipairs(cfg.rewardList) do
        local item_id = reward.itemID
        local count = reward.count
        if item_id and count and count > 0 then
            if not bag.add_item(item_id, count) then
                return { error_code = const.error_code.add_item_failed }
            end
            table.insert(bag_update_list, {
                item_id = item_id,
                item_count = bag.get_item_count(item_id),
            })
        end
    end
    M.update_task(task_index, { status = const.task_status.received })
    M.push_task_update({ build_task_info(row) })
    if #bag_update_list > 0 then
        _GLOBAL.push_client("update_bag_item_list", { info_list = bag_update_list })
    end
    return { error_code = const.error_code.success }
end

--@data_desc
function M.showWorldAgentData(data_desc)
    local data_map = {
        ["task"] = _TASK_LIST,
    }
    local data = data_map[data_desc]
    if not data then
        return "data not found"
    end
    return util.serialize(data)
end

return M
