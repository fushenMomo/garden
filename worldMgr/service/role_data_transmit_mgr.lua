local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local data_access = require "common.data_access"

local _SERVER_ID = nil
local EMPTY = {}

local CMD = {}

local function fetch_from_world(server_id, proc_id, role_dbid, cmd, args)
    return cluster.call(
        string.format("world_%s_%s", server_id, proc_id),
        ".handle_message",
        "agent_cmd_by_role_dbid",
        role_dbid, cmd, table.unpack(args)
    )
end

function CMD.query_role_data_local(role_dbid, cmd, ...)
    role_dbid = tonumber(role_dbid)
    if not role_dbid then
        return EMPTY
    end
    local proc_id = tonumber(data_access.is_role_online(_SERVER_ID, role_dbid))
    if not proc_id then
        return EMPTY
    end
    local args = {...}
    local ok, ret = pcall(function()
        return fetch_from_world(_SERVER_ID, proc_id, role_dbid, cmd, args)
    end)
    if not ok then
        logger.error("query_role_data_local failed, role_dbid=%s, cmd=%s, err=%s", role_dbid, cmd, tostring(ret))
        return EMPTY
    end
    return ret or EMPTY
end

function CMD.query_role_data(target_server_id, role_dbid, cmd, ...)
    target_server_id = tonumber(target_server_id)
    role_dbid = tonumber(role_dbid)
    if not target_server_id or not role_dbid or not cmd then
        return EMPTY
    end
    local args = {...}
    if target_server_id == tonumber(_SERVER_ID) then
        return CMD.query_role_data_local(role_dbid, cmd, table.unpack(args))
    end
    local ok, ret = pcall(function()
        return cluster.call("serverMgr", ".handle_message",
            "relay_role_data_query", target_server_id, role_dbid, cmd, table.unpack(args))
    end)
    if not ok then
        logger.error("query_role_data cross server failed, target_server_id=%s, role_dbid=%s, cmd=%s, err=%s",
            target_server_id, role_dbid, cmd, tostring(ret))
        return EMPTY
    end
    return ret or EMPTY
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, CMD, cmd, ...)
    end)

    _SERVER_ID = tonumber(skynet.getenv("server_id"))
    skynet.register(".role_data_transmit_mgr")
    logger.info("role_data_transmit_mgr started, server_id=%s", _SERVER_ID)
end)
