local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local sharedata = require "skynet.sharedata"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"

local const = nil
local _SERVER_ID = nil
local _GUILD_ID = nil
local _GUILD_DATA = {}
local _GUILD_MEMBER_MAP = {}
local _GUILD_MEMBER_ROLE_DBID_2_INDEX = {}
local _MAX_MEMBER_INDEX = 0

local function load_guild_data()
    local ret, result = skynet.call(".db_global", "lua", "select_one_by_key", "guild_data", "guild_id", _GUILD_ID)
    if not ret then
        logger.err("load_guild_data failed, ret: %s", ret)
        return
    end
    if result and next(result) then
        _GUILD_DATA.guild_id = result.guild_id
        _GUILD_DATA.name = result.name
        _GUILD_DATA.brief = result.brief
        _GUILD_DATA.head_id = result.head_id
        _GUILD_DATA.member_count = result.member_count
        _GUILD_DATA.level = result.level
        _GUILD_DATA.exp = result.exp
        _GUILD_DATA.create_time = result.create_time
        _GUILD_DATA.approval_status = result.approval_status
        _GUILD_DATA.req_list = util.unserialize(result.req_list)
        _GUILD_DATA.rename_times = result.rename_times
    end
    logger.info("load_guild_data, ret: %s, result: %s", ret, util.serialize(_GUILD_DATA))
end

local function load_guild_member()
    local ret, result = skynet.call(".db_global", "lua", "select_by_key", "guild_member", "guild_id", _GUILD_ID)
    if not ret then
        logger.err("load_guild_member failed, ret: %s", ret)
        return
    end
    if result and next(result) then
        for _, guild_member in ipairs(result) do
            _GUILD_MEMBER_MAP[guild_member.role_dbid] = guild_member
            _GUILD_MEMBER_ROLE_DBID_2_INDEX[guild_member.role_dbid] = guild_member.index
            if _MAX_MEMBER_INDEX < guild_member.index then
                _MAX_MEMBER_INDEX = guild_member.index
            end
        end
    end
    logger.info("load_guild_member, ret: %s, result: %s", ret, util.serialize(_GUILD_MEMBER_MAP))
end 

local CMD = {}

function CMD.notify_world_0am_update()
    logger.info("guild_%s notify_world_0am_update", _GUILD_ID)
    
end

function CMD.notify_world_6am_update()
    logger.info("guild_%s notify_world_6am_update", _GUILD_ID)
    
end

function CMD.get_guild_info()
    logger.info("guild_%s get_guild_info", _GUILD_ID)
    local msg = {
        guild_id = _GUILD_ID,
        guild_name = _GUILD_DATA.name,
        guild_brief = _GUILD_DATA.brief,
        guild_level = _GUILD_DATA.level,
    }
    return true, msg
end

function CMD.join_guild(msg)
    logger.info("guild_%s join_guild, msg=%s", _GUILD_ID, util.serialize(msg))
    local role_dbid = tonumber(msg.role_dbid)
    if not role_dbid then
        logger.error("join_guild failed, role_dbid=%s", role_dbid)
        return false
    end

    if _GUILD_MEMBER_MAP[role_dbid] then
        logger.error("join_guild already, role_dbid=%s in guild_%s", role_dbid, _GUILD_ID)
        return false
    end

    local new_member = {
        guild_id = _GUILD_ID,
        role_dbid = role_dbid,
        index = _MAX_MEMBER_INDEX + 1,
        sex = 0,
        standing = const.guild_standing.member,
        name = "",
        fighting_value = 0,
        logout_time = 0,
        join_time = os.time(),
    }
    local ok = skynet.call(".db_global", "lua", "insert", "guild_member", new_member)
    if not ok then
        logger.error("join_guild failed, role_dbid=%s", role_dbid)
        return false
    end
    _GUILD_MEMBER_MAP[role_dbid] = new_member
    _GUILD_MEMBER_ROLE_DBID_2_INDEX[role_dbid] = new_member.index

    _GUILD_DATA.member_count = _GUILD_DATA.member_count + 1
    ok = skynet.call(".db_global", "lua", "update", "guild_data", 
        "guild_id", _GUILD_ID, {
        member_count = _GUILD_DATA.member_count,
    })
    if not ok then
        logger.error("join_guild failed, guild_id=%s", _GUILD_ID)
        return false
    end
    return true
end

function CMD.login_guild(msg)
    logger.info("guild_%s login_guild, msg=%s", _GUILD_ID, util.serialize(msg))
    local role_dbid = tonumber(msg.role_dbid)
    if not role_dbid then
        logger.error("login_guild failed, role_dbid=%s", role_dbid)
        return false
    end
    if not _GUILD_MEMBER_MAP[role_dbid] then
        logger.error("login_guild failed, role_dbid=%s not in guild_%s", role_dbid, _GUILD_ID)
        return false
    end

    _GUILD_MEMBER_MAP[role_dbid].logout_time = 0 -- 修改成在线状态
    local ok = skynet.call(".db_global", "lua", "update_by_conditions", "guild_member", {
        guild_id = _GUILD_ID,
        index = _GUILD_MEMBER_MAP[role_dbid].index,
    }, {
        logout_time = 0,
    })
    if not ok then
        logger.error("login_guild failed, guild_id=%s, role_dbid=%s", _GUILD_ID, role_dbid)
        return false
    end

    return true
end

function CMD.logout_guild(msg)
    logger.info("guild_%s logout_guild, msg=%s", _GUILD_ID, util.serialize(msg))
    local role_dbid = tonumber(msg.role_dbid)
    if not role_dbid then
        logger.error("logout_guild failed, role_dbid=%s", role_dbid)
        return false
    end
    if not _GUILD_MEMBER_MAP[role_dbid] then
        logger.error("logout_guild failed, role_dbid=%s not in guild_%s", role_dbid, _GUILD_ID)
        return false
    end

    _GUILD_MEMBER_MAP[role_dbid].logout_time = os.time() -- 修改成离线状态
    local ok = skynet.call(".db_global", "lua", "update_by_conditions", "guild_member", {
        guild_id = _GUILD_ID,
        index = _GUILD_MEMBER_MAP[role_dbid].index,
    }, {
        logout_time = _GUILD_MEMBER_MAP[role_dbid].logout_time,
    })
    if not ok then
        logger.error("logout_guild failed, guild_id=%s, role_dbid=%s", _GUILD_ID, role_dbid)
        return false
    end

    return true
end

function CMD.change_guild_desc(msg)
    logger.info("guild_%s change_guild_desc, msg=%s", _GUILD_ID, util.serialize(msg))
    local guild_name = msg.guild_name
    local guild_brief = msg.guild_brief
    if not guild_name or not guild_brief then
        logger.error("change_guild_desc failed, guild_name=%s, guild_brief=%s", guild_name, guild_brief)
        return false
    end

    local ok = skynet.call(".db_global", "lua", "update", "guild_data", 
        "guild_id", _GUILD_ID, {
        name = guild_name,
        brief = guild_brief,
    })
    if not ok then
        logger.error("change_guild_desc failed, guild_id=%s", _GUILD_ID)
        return false
    end

    return true
end

function CMD.create_guild(msg)
    logger.info("guild_%s create_guild, msg=%s", _GUILD_ID, util.serialize(msg))
    local role_dbid = tonumber(msg.role_dbid)
    if not role_dbid then
        logger.error("create_guild failed, role_dbid=%s", role_dbid)
        return false
    end

    if _GUILD_MEMBER_MAP[role_dbid] then
        logger.error("create_guild already, role_dbid=%s in guild_%s", role_dbid, _GUILD_ID)
        return false
    end
    
    local new_member = {
        guild_id = _GUILD_ID,
        index = _MAX_MEMBER_INDEX + 1,
        role_dbid = role_dbid,  
        sex = 0,
        standing = const.guild_standing.ownner,
        name = "",
        fighting_value = 0,
        logout_time = 0,
        join_time = os.time(),
    }
    local ok, index = skynet.call(".db_global", "lua", "insert", "guild_member", new_member)

    if not ok then
        logger.error("create_guild failed, role_dbid=%s", role_dbid)
        return false
    end
    _GUILD_MEMBER_MAP[role_dbid] = new_member
    _GUILD_MEMBER_ROLE_DBID_2_INDEX[role_dbid] = new_member.index

    return true
end

function CMD.start(info)
    _GUILD_ID = tonumber(info.guild_id)
    load_guild_data()
    load_guild_member()
    skynet.register(".guild_" .. _GUILD_ID)
    return true
end

skynet.init(function()
    const = sharedata.query "const"
    _SERVER_ID = skynet.getenv("server_id")
end)

skynet.start(function()
	skynet.dispatch("lua", function(session, _, cmd, ...)
		snutil.lua_docmd(session, CMD, cmd, ...)
	end)

	logger.info("guild started")
end)
