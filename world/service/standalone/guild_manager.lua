local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local sharedata = require "skynet.sharedata"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"

local const = nil

local _GUILD_AGENT_LIST = {}

local CMD = {}

function CMD.notify_world_0am_update()
    logger.info("guild_manager notify_world_0am_update")
    if _GUILD_AGENT_LIST and next(_GUILD_AGENT_LIST) then
        for guild_id, guild_agent in pairs(_GUILD_AGENT_LIST) do
            skynet.send(guild_agent, "lua", "notify_world_0am_update")
        end
    end
end

function CMD.notify_world_6am_update()
    logger.info("guild_manager notify_world_6am_update")
    if _GUILD_AGENT_LIST and next(_GUILD_AGENT_LIST) then
        for guild_id, guild_agent in pairs(_GUILD_AGENT_LIST) do
            skynet.send(guild_agent, "lua", "notify_world_6am_update")
        end
    end
end

function CMD.login_guild(msg)
    logger.info("guild_manager login_guild, msg=%s", util.serialize(msg))
    local guild_id = tonumber(msg.guildID)
    local role_dbid = tonumber(msg.roleDBID)
    if (not guild_id) or (not role_dbid) then
        logger.error("login_guild111 failed, guild_id=%s, role_dbid=%s", guild_id, role_dbid)
        return false
    end

    local guild_agent = _GUILD_AGENT_LIST[guild_id]
    if not guild_agent then
        logger.error("login_guild222 failed, guild_id=%s, role_dbid=%s", guild_id, role_dbid)
        return false
    end
    local ret = skynet.call(guild_agent, "lua", "login_guild", {
        role_dbid = role_dbid
    })
    return ret
end

function CMD.logout_guild(msg)
    logger.info("guild_manager logout_guild, msg=%s", util.serialize(msg))
    local guild_id = tonumber(msg.guildID)
    local role_dbid = tonumber(msg.roleDBID)
    if not guild_id or not role_dbid then
        logger.error("logout_guild failed, guild_id=%s, role_dbid=%s", guild_id, role_dbid)
        return false
    end

    local guild_agent = _GUILD_AGENT_LIST[guild_id]
    if not guild_agent then
        logger.error("logout_guild failed, guild_id=%s, role_dbid=%s", guild_id, role_dbid)
        return false
    end
    local ret = skynet.call(guild_agent, "lua", "logout_guild", {
        role_dbid = role_dbid
    })
    return ret
end

function CMD.change_guild_desc(msg)
    logger.info("guild_manager change_guild_desc, msg=%s", util.serialize(msg))
    local guild_id = tonumber(msg.guild_id)
    local guild_name = msg.guild_name
    local guild_brief = msg.guild_brief
    if not guild_id or not guild_name or not guild_brief then
        logger.error("change_guild_desc failed, guild_id=%s, guild_name=%s, guild_brief=%s", guild_id, guild_name, guild_brief)
        return false
    end

    local guild_agent = _GUILD_AGENT_LIST[guild_id]
    if not guild_agent then
        logger.error("change_guild_desc failed, guild_id=%s", guild_id)
        return false
    end
    local ret = skynet.call(guild_agent, "lua", "change_guild_desc", {
        guild_name = guild_name,
        guild_brief = guild_brief,
    })
    return ret
end

function CMD.create_guild(msg)
    logger.info("guild_manager create_guild, msg=%s", util.serialize(msg))
    local guild_name = msg.guild_name
    local guild_brief = msg.guild_brief
    local role_dbid = tonumber(msg.role_dbid)
    if not guild_name or not guild_brief or not role_dbid then
        logger.error("create_guild failed, guild_name=%s, guild_brief=%s, role_dbid=%s", guild_name, guild_brief, role_dbid)
        return false
    end

    local ok, guild_id = skynet.call(".db_global", "lua", "insert", "guild_data", {
        name = guild_name,
        brief = guild_brief,
        head_id = 0,
        member_count = 1,
        level = 1,
        exp = 0,
        create_time = os.time(),
        approval_status = 0,
        req_list = util.serialize({}),
        rename_times = 0,
    })
    if not ok then
        logger.error("create_guild failed, guild_name=%s, guild_brief=%s", guild_name, guild_brief)
        return false
    end

    logger.info("create_guild success, guild_id=%s, role_dbid=%s", guild_id, role_dbid)

    local guild_agent = skynet.newservice("service/standalone/guild")
    _GUILD_AGENT_LIST[guild_id] = guild_agent
    local ret = skynet.call(guild_agent, "lua", "start", {
        guild_id = guild_id,
    })
    if not ret then
        logger.error("create_guild failed, guild_id=%s", guild_id)
        return false
    end
    ret = skynet.call(guild_agent, "lua", "create_guild", {role_dbid = role_dbid})
    if not ret then
        logger.error("create_guild failed, role_dbid=%s", role_dbid)
        return false
    end
    return ret, guild_id
end

function CMD.get_guild_info(msg)
    logger.info("guild_manager get_guild_info, msg=%s", util.serialize(msg))
    local guild_id = tonumber(msg.guildID)
    if not guild_id then
        logger.error("get_guild_info failed, guild_id=%s", guild_id)
        return false
    end

    local guild_agent = _GUILD_AGENT_LIST[guild_id]
    if not guild_agent then
        logger.error("get_guild_info failed, guild_id=%s", guild_id)
        return false
    end
    local ret, msg = skynet.call(guild_agent, "lua", "get_guild_info")
    if not ret then
        logger.error("get_guild_info failed, guild_id=%s", guild_id)
        return false
    end
    return ret, msg
end

function CMD.get_guild_list()
    logger.info("guild_manager get_guild_list")
    local msg = {
        info_list = {},
    }

    if _GUILD_AGENT_LIST and next(_GUILD_AGENT_LIST) then
        for guild_id, guild_agent in pairs(_GUILD_AGENT_LIST) do
            local ret, info = skynet.call(guild_agent, "lua", "get_guild_info")
            if ret then
                table.insert(msg.info_list, info)
            end
        end
    end
    return true, msg
end

function CMD.join_guild(msg)
    logger.info("guild_manager join_guild, msg=%s", util.serialize(msg))
    local guild_id = tonumber(msg.guild_id)
    local role_dbid = tonumber(msg.role_dbid)
    if not guild_id then
        logger.error("join_guild failed, guild_id=%s", guild_id)
        return false
    end

    local guild_agent = _GUILD_AGENT_LIST[guild_id]
    if not guild_agent then
        logger.error("join_guild failed, guild_id=%s", guild_id)
        return false
    end
    local ret = skynet.call(guild_agent, "lua", "join_guild", {
        role_dbid = role_dbid,
    })
    return ret
end

-- 加载公会数据列表
local function load_guild_list()
    local sql = "SELECT guild_id FROM guild_data"
    local ret, result = skynet.call(".db_global", "lua", "execute", sql)
    if not ret then
        logger.err("load_guild_list failed, ret: %s", ret)
        return
    end
    if result and next(result) then
        for _, guild_data in ipairs(result) do
            local guild_id = guild_data.guild_id
            local guild_agent = skynet.newservice("service/standalone/guild")
            _GUILD_AGENT_LIST[guild_id] = guild_agent
            skynet.call(guild_agent, "lua", "start", {
                guild_id = guild_id,
            })
        end
    end
end


skynet.init(function()
    const = sharedata.query "const"
end)

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)

    load_guild_list()

    skynet.register(".guild_manager")
	logger.info("guild_manager started")
end)
