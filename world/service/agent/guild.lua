local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local data_access = require "common.data_access"

local const = require "common.const"

local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil
local _GUILD_DATA = nil
local player = nil

M.REQUEST = REQUEST
M.CMD = CMD

local function get_world_mgr_name()
    local dest_cluster_name = "worldMgr_" .. _GLOBAL._SERVER_ID .. "_1"
    return dest_cluster_name
end

--@global
function M.init(global)
    logger.info("guild init")
    _GLOBAL = global
    player = require "world.service.agent.player"
end

function M.load_data()
    logger.info("guild load_data")  
    _GUILD_DATA = data_access.load("role_guild", { parentDBID = player.get_role_base_dbid() })
    if not _GUILD_DATA then
        local ok = data_access.insert("role_guild", { parentDBID = player.get_role_base_dbid() })
        if not ok then
            return
        end
        _GUILD_DATA = data_access.load("role_guild", { parentDBID = player.get_role_base_dbid() })
    end
end

function M.tick()
    --logger.info("guild tick")
end

local function request_guild_info(guildID)
    local dest_cluster_name = get_world_mgr_name()
    local msg = {
        guildID = guildID,
    }
    local ret, msg = cluster.call(
                                dest_cluster_name, 
                                ".handle_message", 
                                "get_guild_info", 
                                msg 
                            )
    logger.info("request_guild_info, ret: %s, msg: %s", ret, util.serialize(msg))
    if not ret then
        logger.error("get_guild_info failed, ret: %s", ret)
        return
    end
    
    _GLOBAL.push_client("update_guild_info", {
        info = msg,
    })
end

function M.load_complete()
    logger.info("guild load_complete")
    if (not _GUILD_DATA) or (_GUILD_DATA.guildID == 0) then
        return
    end
    if _GUILD_DATA and _GUILD_DATA.guildID and _GUILD_DATA.guildID > 0 then
        -- 发送login_guild消息给guild_manager
        local dest_cluster_name = get_world_mgr_name()
        local msg = {
            guildID = _GUILD_DATA.guildID,
            roleDBID = player.get_role_base_dbid(),
        }
        local ret = cluster.call(
                                    dest_cluster_name, 
                                    ".handle_message", 
                                    "login_guild", 
                                    msg
                                )
        if not ret then
            logger.error("login_guild failed, ret: %s", ret)
            return
        end
        request_guild_info(_GUILD_DATA.guildID)
    end
end

function M.sync_data()
    logger.info("guild sync_data")

end

function M.onToday0am()
    logger.info("guild onToday0am")
end

function M.onToday6am()
    logger.info("guild onToday6am")
end

function M.close()
    logger.info("guild close")
    if _GUILD_DATA and _GUILD_DATA.guildID and _GUILD_DATA.guildID > 0 then
        -- 发送logout_guild消息给guild_manager
        local dest_cluster_name = get_world_mgr_name()
        local msg = {
            guildID = _GUILD_DATA.guildID,
            roleDBID = player.get_role_base_dbid(),
        }
        local ret = cluster.call(
                                    dest_cluster_name, 
                                    ".handle_message", 
                                    "logout_guild", 
                                    msg
                                )
        if not ret then
            logger.error("logout_guild failed, ret: %s", ret)
            return
        end
    end
end



function REQUEST:create_guild()
    logger.info("guild createGuild")
    if _GUILD_DATA and _GUILD_DATA.guildID and _GUILD_DATA.guildID > 0 then
        return {error_code = const.error_code.already_in_guild}
    end
    
    local guild_name = self.guild_name
    if not guild_name then
        return {error_code = const.error_code.invalid_guild_name}
    end
    local guild_brief = self.guild_brief
    if not guild_brief then
        return {error_code = const.error_code.invalid_guild_brief}
    end

    -- 发送消息给guild_manager
    local dest_cluster_name = get_world_mgr_name()
    logger.info("createGuild, dest_cluster_name: %s", dest_cluster_name)
    local msg = {
        guild_name = guild_name,
        guild_brief = guild_brief,
        role_dbid = player.get_role_base_dbid(),
    }
    local ret, guild_id = cluster.call(
                                dest_cluster_name, 
                                ".handle_message", 
                                "create_guild", 
                                msg
                            )
    logger.info("createGuild, ret: %s, guild_id: %s", ret, guild_id)
    if not ret then
        logger.error("create_guild failed, ret: %s", ret)
        return {error_code = const.error_code.create_guild_failed}
    end

    _GUILD_DATA.guildID = guild_id
    _GUILD_DATA.guildTitle = const.guild_standing.ownner
    data_access.save("role_guild", _GUILD_DATA, {"guildID", "guildTitle"})

    request_guild_info(_GUILD_DATA.guildID)

    return {error_code = const.error_code.success}
end


function REQUEST:get_guild_list()
    logger.info("guild getGuildList")
    local dest_cluster_name = get_world_mgr_name()
    local ret, msg = cluster.call(
                                dest_cluster_name, 
                                ".handle_message", 
                                "get_guild_list"
                            )
    logger.info("getGuildList, ret: %s, msg: %s", ret, util.serialize(msg))
    if not ret then
        logger.error("get_guild_list failed, ret: %s", ret)
        return {error_code = const.error_code.get_guild_list_failed}
    end
    return {error_code = const.error_code.success, info_list = msg.info_list}
end


function REQUEST:change_guild_desc()
    logger.info("guild changeGuildDesc")
    if not (_GUILD_DATA and _GUILD_DATA.guildID and _GUILD_DATA.guildID > 0) then
        return {error_code = const.error_code.not_in_guild}
    end

    if _GUILD_DATA.guildTitle ~= const.guild_standing.ownner then
        return {error_code = const.error_code.not_guild_ownner}
    end

    local guild_id = _GUILD_DATA.guildID

    local guild_name = self.guild_name
    if not guild_name then
        return {error_code = const.error_code.invalid_guild_name}
    end
    local guild_brief = self.guild_brief
    if not guild_brief then
        return {error_code = const.error_code.invalid_guild_brief}
    end

    local dest_cluster_name = get_world_mgr_name()
    local msg = {
        guild_id = guild_id,
        guild_name = guild_name,
        guild_brief = guild_brief,
    }
    local ret = cluster.call(
                                dest_cluster_name, 
                                ".handle_message", 
                                "change_guild_desc", 
                                msg
                            )
    logger.info("changeGuildDesc, ret: %s", ret)
    if not ret then
        logger.error("change_guild_desc failed, ret: %s", ret)
        return {error_code = const.error_code.change_guild_desc_failed}
    end

    return {error_code = const.error_code.success, guild_name = guild_name, guild_brief = guild_brief}
end

function REQUEST:join_guild()
    logger.info("guild joinGuild")
    if _GUILD_DATA and _GUILD_DATA.guildID and _GUILD_DATA.guildID > 0 then
        return {error_code = const.error_code.already_in_guild}
    end

    local guild_id = tonumber(self.guild_id)
    if not guild_id then
        return {error_code = const.error_code.invalid_guild_id}
    end

    local dest_cluster_name = get_world_mgr_name()
    local msg = {
        guild_id = guild_id,
        role_dbid = player.get_role_base_dbid(),
    }
    local ret = cluster.call(
                                dest_cluster_name, 
                                ".handle_message",
                                "join_guild",
                                msg
                            )
    logger.info("joinGuild, ret: %s", ret)
    if not ret then
        logger.error("join_guild failed, ret: %s", ret)
        return {error_code = const.error_code.join_guild_failed}
    end

    _GUILD_DATA.guildID = guild_id
    data_access.save("role_guild", _GUILD_DATA, {"guildID"})

    request_guild_info(_GUILD_DATA.guildID)

    return {error_code = const.error_code.success}
end

--@data_desc
function M.showWorldAgentData(data_desc)
    local data_map = {
        ["role_guild"] = _GUILD_DATA,
    }
    local data = data_map[data_desc]
    if not data then
        return "data not found"
    end
    return util.serialize(data)
end

return M