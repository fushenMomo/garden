local skynet = require "skynet"

local M = {}

local function wait_call_with_timeout(address, timeout_ms, cmd, ...)
    local done = false
    local wakeup_token = {}
    local result = nil
    local err = nil

    skynet.fork(function(...)
        local packed = table.pack(pcall(skynet.call, address, "lua", cmd, ...))
        local ok = packed[1]
        if ok then
            result = table.pack(table.unpack(packed, 2, packed.n))
        else
            err = packed[2]
        end
        done = true
        skynet.wakeup(wakeup_token)
    end, ...)

    skynet.timeout(math.max(1, math.floor(timeout_ms / 10)), function()
        if done then
            return
        end
        err = string.format("rpc timeout cmd=%s timeout_ms=%s", tostring(cmd), tostring(timeout_ms))
        done = true
        skynet.wakeup(wakeup_token)
    end)

    skynet.wait(wakeup_token)
    return result, err
end

local function query_service(name)
    local registry = skynet.localname(".svc_registry")
    if not registry then
        return nil, "service registry not started"
    end
    local ok, address = pcall(skynet.call, registry, "lua", "query", name)
    if not ok then
        return nil, address
    end
    if not address then
        return nil, string.format("service not found: %s", tostring(name))
    end
    return address
end

function M.call(service_name, cmd, args, opts)
    opts = opts or {}
    args = args or {}

    local timeout_ms = opts.timeout_ms or 1000
    local retries = opts.retries or 0
    local retry_sleep_ms = opts.retry_sleep_ms or 100

    local address, query_err = query_service(service_name)
    if not address then
        return nil, query_err
    end

    local last_err = nil
    for i = 0, retries do
        local result, err = wait_call_with_timeout(address, timeout_ms, cmd, table.unpack(args))
        if not err then
            local result_pack = result or { n = 0 }
            return table.unpack(result_pack, 1, result_pack.n)
        end
        last_err = err

        if i < retries then
            skynet.sleep(math.max(1, math.floor(retry_sleep_ms / 10)))
        end
    end

    return nil, string.format("rpc failed service=%s cmd=%s err=%s", tostring(service_name), tostring(cmd), tostring(last_err))
end

function M.send(service_name, cmd, args)
    args = args or {}
    local address, query_err = query_service(service_name)
    if not address then
        return nil, query_err
    end
    skynet.send(address, "lua", cmd, table.unpack(args))
    return true
end

return M
