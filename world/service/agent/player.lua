local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local data_access = require "common.data_access"

local const = require "common.const"

local _PLAYER_DATA = nil
local _ROLE_BASE = nil
local _ROLE_DATA = nil
local _LOGIN_TIME = nil


local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil

M.REQUEST = REQUEST
M.CMD = CMD

--检查玩家是否有角色
local function check_role_list()
    if not _PLAYER_DATA then
        return false
    end

    local check_list = {"role1", "role2", "role3", "role4"}
    for _, role_name in ipairs(check_list) do
        if _PLAYER_DATA[role_name] and _PLAYER_DATA[role_name] ~= 0 then
            return true
        end
    end
    return false
end

local function create_role()
    local ok, dbid = data_access.insert("role_base", {
        actID = _PLAYER_DATA.actID,
        serverID = _PLAYER_DATA.serverID,
        createTime = os.time(),
        sex = const.sex.boy,
        name = "test_role_" .. _PLAYER_DATA.actID,
    })
    if not ok or not dbid then
        return
    end

    data_access.insert("role_data", { parentDBID = dbid })
    data_access.insert("role_guild", { parentDBID = dbid })
    _PLAYER_DATA.selectRole = dbid
    _PLAYER_DATA.role1 = dbid
    data_access.save("player_data", _PLAYER_DATA)

    logger.info("create_role success, role_id=%s", dbid)
    _ROLE_BASE = data_access.load("role_base", { dbid = dbid })
    _ROLE_DATA = data_access.load("role_data", { parentDBID = dbid })
    if not _ROLE_DATA then
        ok = data_access.insert("role_data", { parentDBID = dbid })
        if not ok then
            return
        end
        _ROLE_DATA = data_access.load("role_data", { parent_dbid = dbid })
    end
end

local function load_role()
    if not _PLAYER_DATA then
        return
    end
    local dbid = _PLAYER_DATA.selectRole
    _ROLE_BASE = data_access.load("role_base", { dbid = dbid })
    if not _ROLE_BASE then
        logger.error("load_role_base failed, role_id=%s", dbid)
        return
    end
    _ROLE_DATA = data_access.load("role_data", { parentDBID = _ROLE_BASE.dbid })
    if not _ROLE_DATA then
        local ok = data_access.insert("role_data", { parentDBID = _ROLE_BASE.dbid })
        if not ok then
            return
        end
        _ROLE_DATA = data_access.load("role_data", { parentDBID = _ROLE_BASE.dbid })
    end
end

local function load_data()
    local result = data_access.load("player_data", { actID = _GLOBAL._ACC_ID, serverID = _GLOBAL._SERVER_ID })
    if not result then
        local ok = data_access.insert("player_data", {
            actID = _GLOBAL._ACC_ID,
            serverID = _GLOBAL._SERVER_ID,
            createTime = os.time(),
        })
        if not ok then
            logger.error("load_data failed, acc_id=%s, server_id=%s", _GLOBAL._ACC_ID, _GLOBAL._SERVER_ID)
            return
        else
            result = data_access.load("player_data", { actID = _GLOBAL._ACC_ID, serverID = _GLOBAL._SERVER_ID })
        end
    end
    _PLAYER_DATA = result
    _PLAYER_DATA.online = 1
    _LOGIN_TIME = os.time()
    data_access.save("player_data", _PLAYER_DATA, {"online"})
    data_access.set_online(_GLOBAL._SERVER_ID, _GLOBAL._ACC_ID, _LOGIN_TIME)
    logger.info("load_data success, acc_id=%s, server_id=%s, player_data=%s", 
                _GLOBAL._ACC_ID, _GLOBAL._SERVER_ID, util.serialize(_PLAYER_DATA))

    if not _PLAYER_DATA then
        return
    end

    if not check_role_list() then
        create_role()
    else
        load_role()
    end

end

function REQUEST:changeRoleName()
    local new_name = self.new_name
    if not new_name or new_name == "" then
        return { error_code = const.error_code.invalid_params }
    end
    if #new_name > 32 then
        return { error_code = const.error_code.role_name_too_long }
    end
    _ROLE_BASE.name = new_name
    data_access.save("role_base", _ROLE_BASE, {"name"})
    logger.info("changeRoleName success, role_id=%s, new_name=%s", _ROLE_BASE.dbid, new_name)
    return { error_code = const.error_code.success, new_name = new_name }
end


--@global
function M.init(global)
    logger.info("player init")
    _GLOBAL = global
end

function M.load_data()
    logger.info("player load_data")
    load_data()
end

function M.load_complete()
    logger.info("player load_complete")

end

function M.sync_data()
    logger.info("player sync_data")
    if not _PLAYER_DATA or not _ROLE_BASE then
        return
    end
    logger.info("player sync_data, _GLOBAL=%s", util.serialize(_GLOBAL))
    _GLOBAL.push_client("update_role_list", {
        sel_role = _PLAYER_DATA.selectRole,
        role_list = {
            {
                role_id = _ROLE_BASE and _ROLE_BASE.dbid or 0,
                name = _ROLE_BASE and _ROLE_BASE.name or "",
                sex = _ROLE_BASE and _ROLE_BASE.sex or 0,
            },
        },
    })
end

function M.tick()
    --logger.info("player tick")
end

function M.onToday0am()
    logger.info("player onToday0am")
end

function M.onToday6am()
    logger.info("player onToday6am")
end

function M.close()
    logger.info("player close")
    if _PLAYER_DATA then
        _PLAYER_DATA.online = 0
        _PLAYER_DATA.onlineTime = _PLAYER_DATA.onlineTime + (os.time() - _LOGIN_TIME)
        data_access.save("player_data", _PLAYER_DATA, {"online", "onlineTime"})
    end
    data_access.set_offline(_GLOBAL._SERVER_ID, _GLOBAL._ACC_ID)
end

function M.get_role_base_dbid()
    return _ROLE_BASE and _ROLE_BASE.dbid or 0
end

function M.get_role_data()
    return _ROLE_DATA
end

function M.get_player_data()
    return _PLAYER_DATA
end

return M