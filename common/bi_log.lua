local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local bi_queue = require "common.bi_queue"

local M = {}

local function build_source()
    local nodename = skynet.getenv("nodename") or "unknown"
    local server_id = skynet.getenv("server_id")
    local proc_id = skynet.getenv("proc_id")
    if server_id and proc_id then
        return string.format("%s_%s_%s", nodename, server_id, proc_id)
    end
    return nodename
end

local function build_entry(data)
    return {
        ts = os.time(),
        source = build_source(),
        data = data,
    }
end

local function bi_cluster_name(server_id)
    return string.format("bi_%s_1", tostring(server_id))
end

function M.push(server_id, data)
    server_id = tonumber(server_id)
    if not server_id or not data then
        return false
    end
    local entry = build_entry(data)
    if skynet.localname(".redis") then
        return bi_queue.push(server_id, entry)
    end
    pcall(cluster.send, bi_cluster_name(server_id), ".bi_push", "push", entry)
    return true
end

return M
