local logger = require "common.logger"
local data_access = require "common.data_access"
local json = require "common.json_min"
local util = require "common.util"
local sharedata = require "skynet.sharedata"

local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil
local player = nil
local const = nil
local cfg_partner = nil
local _task = nil

local _PARTNER_LIST = nil
local _PARTNER_MAP = nil
local _MAX_PARTNER_INDEX = 0

M.REQUEST = REQUEST
M.CMD = CMD

function M.init(global)
    _GLOBAL = global
    player = require "world.service.agent.player"
	_task = require "world.service.agent.task"
    const = sharedata.query("const")
    cfg_partner = sharedata.query("cfg_partner")
end

local function rebuild_partner_map()
    _PARTNER_MAP = {}
    for _, row in ipairs(_PARTNER_LIST or {}) do
        _PARTNER_MAP[row.partnerIndex] = row
        if row.partnerIndex > _MAX_PARTNER_INDEX then
            _MAX_PARTNER_INDEX = row.partnerIndex
        end
    end
end

local function next_partner_index()
    _MAX_PARTNER_INDEX = _MAX_PARTNER_INDEX + 1
    return _MAX_PARTNER_INDEX
end


local function build_partner_info(row)
    return {
        partner_index = row.partnerIndex,
        partner_id = row.partnerID or 0,
        level = row.level or 0,
        grade = row.grade or 0,
        maxhp = row.maxhp or 0,
        speed = row.speed or 0,
        attack = row.attack or 0,
        defense = row.defense or 0,
        crit = row.crit or 0,
        de_crit = row.deCrit or 0,
        crit_dam = row.critDam or 0,
        de_crit_dam = row.deCritDam or 0,
        acc = row.acc or 0,
        miss = row.miss or 0,
        incr_dam = row.incrDam or 0,
        decr_dam = row.decrDam or 0,
        cure = row.cure or 0,
        be_cured = row.beCured or 0,
        control = row.control or 0,
        de_control = row.deControl or 0,
        phy_dam = row.phyDam or 0,
        de_phy_dam = row.dePhyDam or 0,
        eng_dam = row.engDam or 0,
        de_eng_dam = row.deEngDam or 0,
        cure_crit = row.cureCrit or 0,
        fv = row.fv or 0,
        lock = row.lock or 0,
        weapon1 = row.weapon1 or 0,
        weapon2 = row.weapon2 or 0,
        weapon3 = row.weapon3 or 0,
        weapon4 = row.weapon4 or 0,
        ext_buff = row.extBuff,
        skill_list = row.skillList,
        chips = row.chips,
    }
end

function M.load_data()
    _PARTNER_LIST = data_access.load_many("partner_list", { parentDBID = player.get_role_base_dbid() }) or {}
    rebuild_partner_map()
    logger.info("partner load_data success, count=%s", #_PARTNER_LIST)
end

function M.load_complete()
    _task.on_complete_event(const.task_complete_type.partner_count)
end

function M.tick()
end

function M.push_partner_update(info_list)
    _GLOBAL.push_client("update_partner_list", {
        info_list = info_list,
    })
end

function M.sync_data()
    local info_list = {}
    for _, row in ipairs(_PARTNER_LIST or {}) do
        table.insert(info_list, build_partner_info(row))
    end
    M.push_partner_update(info_list)
end

function M.onToday0am()
end

function M.onToday6am()
end

function M.close()
end

function M.get_partner_list()
    return _PARTNER_LIST
end

function M.get_partner(partner_index)
    return _PARTNER_MAP and _PARTNER_MAP[partner_index]
end

function M.get_partner_by_id(partner_id)
    for _, row in ipairs(_PARTNER_LIST or {}) do
        if row.partnerID == partner_id then
            return row
        end
    end
end

function M.get_partner_fight_mirror()
    local sorted = {}
    for _, row in ipairs(_PARTNER_LIST or {}) do
        table.insert(sorted, row)
    end
    table.sort(sorted, function(a, b)
        return (a.fv or 0) > (b.fv or 0)
    end)
    local result = {}
    for i = 1, math.min(5, #sorted) do
        table.insert(result, (sorted[i]))
    end
    return result
end

function CMD.get_partner_fight_mirror()
    return M.get_partner_fight_mirror()
end

--@row partner_list row
local function computer_partner_fv(row)
    local fv = 0
    fv = fv + row.level * 100
    fv = fv + row.grade * 10
    fv = fv + row.maxhp
    fv = fv + row.speed
    fv = fv + row.attack
    fv = fv + row.defense
    return fv
end

function M.add_partner(partner_id, init_fields)
    if not partner_id or partner_id <= 0 then
        return false
    end
    if #(_PARTNER_LIST or {}) >= const.partner.max_count then
        return false
    end
    local partner_index = next_partner_index()
    local row = {
        parentDBID = player.get_role_base_dbid(),
        partnerIndex = partner_index,
        partnerID = partner_id,
        level = 0,
        grade = 0,
        maxhp = 0,
        speed = 0,
        attack = 0,
        defense = 0,
        crit = 0,
        deCrit = 0,
        critDam = 0,
        deCritDam = 0,
        acc = 0,
        miss = 0,
        incrDam = 0,
        decrDam = 0,
        cure = 0,
        beCured = 0,
        control = 0,
        deControl = 0,
        phyDam = 0,
        dePhyDam = 0,
        engDam = 0,
        deEngDam = 0,
        cureCrit = 0,
        fv = 0,
        extBuff = {},
        lock = 0,
        skillList = {},
        chips = {},
        weapon1 = 0,
        weapon2 = 0,
        weapon3 = 0,
        weapon4 = 0,
    }
    local partner_cfg = cfg_partner[partner_id]
    if (not init_fields) and partner_cfg then
        init_fields = {
            level = 1,
            grade = partner_cfg.grade,
            maxhp = partner_cfg.maxHp,
            speed = partner_cfg.speed,
            attack = partner_cfg.attack,
            defense = partner_cfg.defense,
            skillList = { partner_cfg.skill1 or 0, partner_cfg.skill2 or 0, partner_cfg.skill3 or 0, partner_cfg.skill4 or 0 },
        }
    end
    for k, v in pairs(init_fields) do
        row[k] = v
    end
    row.fv = computer_partner_fv(row)
    local ok = data_access.insert("partner_list", row)
    if not ok then
        return false
    end
    table.insert(_PARTNER_LIST, row)
    _PARTNER_MAP[partner_index] = row
    _task.on_complete_event(const.task_complete_type.partner_count)
    return true, row
end

function M.update_partner(partner_index, fields)
    local row = _PARTNER_MAP and _PARTNER_MAP[partner_index]
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
    row.fv = computer_partner_fv(row)
    data_access.save("partner_list", row, changed_fields)
    
    return true
end


function REQUEST:active_partner()
    local partner_id = tonumber(self.partner_id)
    if not partner_id or partner_id <= 0 then
        return { error_code = const.error_code.invalid_params }
    end
    local partner = cfg_partner[partner_id]
    if not partner then
        return { error_code = const.error_code.partner_not_found }
    end

    local ok, row = M.add_partner(partner_id)
    if not ok then
        return { error_code = const.error_code.add_partner_failed }
    end

    M.push_partner_update({ build_partner_info(row) })

    return { error_code = const.error_code.success }
end

--@data_desc
function M.showWorldAgentData(data_desc)
    local data_map = {
        ["partner_list"] = _PARTNER_LIST,
    }
    local data = data_map[data_desc]
    if not data then
        return "data not found"
    end
    return util.serialize(data)
end

return M
