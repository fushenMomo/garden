local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local sharedata = require "skynet.sharedata"
local logger = require "common.logger"
local snutil = require "common.snutil"

local CMD = {}
local const

local function get_group_id(server_id)
    server_id = tonumber(server_id) or 0
    if server_id == 0 then
        return 0
    end
    local ok, info = pcall(cluster.call, "login", ".server_list_service", "get_server_info", server_id)
    if ok and info and info.group_id then
        return tonumber(info.group_id)
    end
    return 0
end

local function upsert(group_id, proc_type, proc_id, proc_name, state)
    local login_db = skynet.localname(".sk_login")
    if not login_db then
        return false, "missing .sk_login"
    end
    local now = os.time()
    local conditions = {
        group_id = group_id,
        proc_type = proc_type,
        proc_id = proc_id,
    }
    local ret, row = skynet.call(login_db, "lua", "select_one_by_conditions", "server_proc_state", conditions)
    if ret and row then
        ret = skynet.call(login_db, "lua", "update_by_conditions", "server_proc_state", conditions, {
            proc_name = proc_name,
            state = state,
            update_time = now,
        })
    else
        ret = skynet.call(login_db, "lua", "insert", "server_proc_state", {
            group_id = group_id,
            proc_type = proc_type,
            proc_id = proc_id,
            proc_name = proc_name,
            state = state,
            update_time = now,
        })
    end
    return ret
end

function CMD.report(server_id, proc_type, proc_id, proc_name, state)
    local group_id = get_group_id(server_id)
    proc_type = tonumber(proc_type)
    proc_id = tonumber(proc_id)
    state = tonumber(state)
    if not proc_type or not proc_id or state == nil then
        return false
    end
    return upsert(group_id, proc_type, proc_id, proc_name or "", state)
end

function CMD.heartbeat(server_id, proc_type, proc_id)
    local group_id = get_group_id(server_id)
    proc_type = tonumber(proc_type)
    proc_id = tonumber(proc_id)
    if not proc_type or not proc_id then
        return false
    end
    local login_db = skynet.localname(".sk_login")
    if not login_db then
        return false
    end
    return skynet.call(login_db, "lua", "update_by_conditions", "server_proc_state", {
        group_id = group_id,
        proc_type = proc_type,
        proc_id = proc_id,
    }, {
        state = const.proc_state.running,
        update_time = os.time(),
    })
end

function CMD.query(group_id)
    group_id = tonumber(group_id)
    if group_id == nil then
        return nil
    end
    local login_db = skynet.localname(".sk_login")
    if not login_db then
        return nil
    end
    local ret, rows = skynet.call(login_db, "lua", "select_by_conditions", "server_proc_state", { group_id = group_id })
    if ret then
        return rows or {}
    end
    return nil
end

local function scan_stale()
    local login_db = skynet.localname(".sk_login")
    if not login_db then
        return
    end
    local threshold = os.time() - const.proc_state_monitor.stale_timeout
    local ret, rows = skynet.call(login_db, "lua", "select_by_conditions", "server_proc_state", {
        state = const.proc_state.running,
    })
    if not ret or not rows then
        return
    end
    for _, row in ipairs(rows) do
        if tonumber(row.update_time) < threshold then
            skynet.call(login_db, "lua", "update_by_conditions", "server_proc_state", {
                group_id = row.group_id,
                proc_type = row.proc_type,
                proc_id = row.proc_id,
            }, {
                state = const.proc_state.closed,
                update_time = os.time(),
            })
            logger.info("proc_state stale closed, group_id=%s proc_type=%s proc_id=%s",
                tostring(row.group_id), tostring(row.proc_type), tostring(row.proc_id))
        end
    end
end

local function scan_loop()
    while true do
        skynet.sleep(const.proc_state_monitor.scan_interval)
        scan_stale()
    end
end

skynet.init(function()
    const = sharedata.query "const"
end)

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, CMD, cmd, ...)
    end)
    skynet.fork(scan_loop)
    skynet.register(".proc_state_service")
    logger.info("proc_state_service started")
end)
