local skynet = require "skynet"
require "skynet.manager"
local const = require "common.const"
local util = require "common.util"

local M = {}

local function redis_addr()
    return skynet.localname(".redis")
end

function M.build_key(server_id)
    return string.format(const.redis_key.bi_queue, tostring(server_id))
end

function M.push(server_id, entry)
    local addr = redis_addr()
    if not addr then
        return false
    end
    local data = util.serialize(entry)
    skynet.send(addr, "lua", "lpush", M.build_key(server_id), data)
    return true
end

function M.pop(server_id)
    local addr = redis_addr()
    if not addr then
        return nil
    end
    return skynet.call(addr, "lua", "rpop", M.build_key(server_id))
end

function M.len(server_id)
    local addr = redis_addr()
    if not addr then
        return 0
    end
    return skynet.call(addr, "lua", "llen", M.build_key(server_id)) or 0
end

return M
