local skynet = require "skynet"
local md5 = require "md5"

local M = {}

local function now_str()
    return os.date("%Y-%m-%d %H:%M:%S")
end

function M.handle(entry)
    local data = entry and entry.data or {}
    local message = tostring(data.message or "")
    if message == "" then
        return false, "empty message"
    end

    local server_id = tonumber(skynet.getenv("server_id"))
    if not server_id then
        return false, "missing server_id"
    end

    local group_id = skynet.call(".server_map", "lua", "get_group_id", server_id)
    if not group_id or group_id == 0 then
        return false, "invalid group_id"
    end

    local hash_key = md5.sumhexa(message)
    local login_db = skynet.localname(".sk_login")
    if not login_db then
        return false, "missing .sk_login"
    end

    local now = now_str()
    local ret, row = skynet.call(login_db, "lua", "select_one_by_conditions", "server_traceback", {
        group_id = group_id,
        hash_key = hash_key,
    })
    if ret and row then
        skynet.call(login_db, "lua", "update", "server_traceback", "id", row.id, {
            last_time = now,
        })
        skynet.call(login_db, "lua", "update_add", "server_traceback", "id", row.id, {
            trace_times = 1,
        })
        return true
    end

    ret = skynet.call(login_db, "lua", "insert", "server_traceback", {
        group_id = group_id,
        hash_key = hash_key,
        traceback_log = message,
        frist_time = now,
        last_time = now,
        trace_times = 1,
        fixed = 0,
    })
    if not ret then
        return false, "insert failed"
    end
    return true
end

return M
