local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local logger = require "common.logger"
local snutil = require "common.snutil"
local cluster_login = require "common.cluster_login"

local REFRESH_INTERVAL = 30000

local _MAP = {}

local CMD = {}

local function apply_list(list)
    if type(list) ~= "table" then
        return
    end
    for id, info in pairs(list) do
        if type(info) == "table" and info.group_id then
            _MAP[tonumber(id)] = tonumber(info.group_id)
        end
    end
end

local function refresh()
    local ok, list = cluster_login.call_any(".server_list_service", "get_server_info_list")
    if not ok then
        logger.error("server_map refresh failed, err=%s", tostring(list))
        return false
    end
    apply_list(list)
    return true
end

function CMD.get_group_id(server_id)
    server_id = tonumber(server_id)
    if not server_id then
        return 0
    end
    if _MAP[server_id] then
        return _MAP[server_id]
    end
    local ok, info = cluster_login.call_any(".server_list_service", "get_server_info", server_id)
    if ok and info and info.group_id then
        _MAP[server_id] = tonumber(info.group_id)
        return _MAP[server_id]
    end
    return 0
end

local function refresh_loop()
    while true do
        skynet.sleep(REFRESH_INTERVAL)
        refresh()
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, CMD, cmd, ...)
    end)
    refresh()
    skynet.fork(refresh_loop)
    skynet.register(".server_map")
    logger.info("server_map service started")
end)
