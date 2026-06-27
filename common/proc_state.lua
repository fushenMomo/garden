local skynet = require "skynet"

local cluster = require "skynet.cluster"

local sharedata = require "skynet.sharedata"

local logger = require "common.logger"



local M = {}



local _heartbeat_running = false

local _const = nil



local PROC_TYPE_MAP = {

    login = "login",

    gateway = "gateway",

    world = "world",

    worldMgr = "worldMgr",

    serverMgr = "serverMgr",

    bi = "bi",

    webAPI = "webAPI",

}



local function get_const()

    if not _const then

        _const = sharedata.query "const"

    end

    return _const

end



local function build_identity()

    local nodename = skynet.getenv("nodename") or "unknown"

    local const = get_const()

    local proc_type_key = PROC_TYPE_MAP[nodename]

    if not proc_type_key then

        return nil

    end

    local proc_type = const.proc_type[proc_type_key]

    local server_id = tonumber(skynet.getenv("server_id")) or 0

    local proc_id = tonumber(skynet.getenv("proc_id")) or 1

    local proc_name

    if server_id > 0 then

        proc_name = string.format("%s_%s_%s", nodename, server_id, proc_id)

    elseif nodename == "login" then

        proc_name = string.format("login_%s", proc_id)

    else

        proc_name = nodename

    end

    return server_id, proc_type, proc_id, proc_name

end



local function get_servermgr_node()

    return "serverMgr"

end



local function call_servermgr_once(cmd, ...)

    local nodename = skynet.getenv("nodename")

    if nodename == "serverMgr" then

        local svc = skynet.localname(".proc_state_service")

        if svc then

            return skynet.call(svc, "lua", cmd, ...)

        end

    end

    return cluster.call(get_servermgr_node(), ".proc_state_service", cmd, ...)

end



local function call_servermgr(cmd, ...)

    local nodename = skynet.getenv("nodename")

    local max_try = (nodename == "serverMgr") and 1 or 30

    local last_err

    for i = 1, max_try do

        local ok, ret = pcall(call_servermgr_once, cmd, ...)

        if ok and ret then

            return true

        end

        last_err = ok and "return false" or ret

        if i < max_try then

            skynet.sleep(100)

        end

    end

    return false, last_err

end



function M.report(state)

    local server_id, proc_type, proc_id, proc_name = build_identity()

    if not proc_type then

        return false

    end

    local ok, err = call_servermgr("report", server_id, proc_type, proc_id, proc_name, state)

    if not ok then

        logger.error("proc_state report failed, state=%s err=%s", tostring(state), tostring(err))

        return false

    end

    return true

end



function M.heartbeat()

    local server_id, proc_type, proc_id = build_identity()

    if not proc_type then

        return false

    end

    local ok, err = call_servermgr("heartbeat", server_id, proc_type, proc_id)

    if not ok then

        logger.error("proc_state heartbeat failed, err=%s", tostring(err))

        return false

    end

    return true

end



function M.running()

    if not M.report(get_const().proc_state.running) then

        return

    end

    if _heartbeat_running then

        return

    end

    _heartbeat_running = true

    local interval = get_const().proc_state_monitor.heartbeat_interval

    skynet.fork(function()

        while _heartbeat_running do

            -- interval 表示间隔多少时间（以 1/100 秒为单位）
            skynet.sleep(interval)
    

            if _heartbeat_running then
                logger.info("proc_state heartbeat_123, interval=%s", interval)
                M.heartbeat()

            end

        end

    end)

end



function M.closed()

    _heartbeat_running = false

    M.report(get_const().proc_state.closed)

end



return M

