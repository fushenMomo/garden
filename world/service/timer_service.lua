local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local const = require "common.const"

local _SERVER_ID
local _PROC_ID
local _QUEUE_KEY
local _DATA_KEY

local _HANDLERS = {}
local _RECOVERED = false

local CMD = {}

local function redis_addr()
    return skynet.address(".redis")
end

local function redis_call(cmd, ...)
    local addr = redis_addr()
    if not addr then
        return nil, "redis not available"
    end
    return skynet.call(addr, "lua", cmd, ...)
end

local function gen_event_id()
    return string.format("%s:%s:%s", _SERVER_ID, _PROC_ID, skynet.genid())
end

local function serialize_event(event_type, payload, fire_at)
    return util.serialize({
        event_type = event_type,
        payload = payload or {},
        fire_at = fire_at,
    })
end

local function parse_event(raw)
    if not raw then
        return nil
    end
    local ok, data = pcall(util.unserialize, raw)
    if not ok or type(data) ~= "table" then
        return nil
    end
    return data
end

local function remove_event(event_id)
    redis_call("zrem", _QUEUE_KEY, event_id)
    redis_call("hdel", _DATA_KEY, event_id)
end

local function dispatch_event(event_id, event)
    local handler = _HANDLERS[event.event_type]
    if not handler then
        logger.warn(
            "timer_service no handler, event_id=%s, event_type=%s",
            event_id,
            event.event_type
        )
        return
    end
    local ok, err = pcall(function()
        skynet.send(
            handler.addr,
            "lua",
            handler.cmd,
            event_id,
            event.event_type,
            event.payload
        )
    end)
    if not ok then
        logger.error(
            "timer_service dispatch failed, event_id=%s, event_type=%s, err=%s",
            event_id,
            event.event_type,
            err
        )
    end
end

local function fire_event(event_id)
    local raw = redis_call("hget", _DATA_KEY, event_id)
    local event = parse_event(raw)
    remove_event(event_id)
    if not event then
        logger.warn("timer_service fire_event missing data, event_id=%s", event_id)
        return false
    end
    logger.info(
        "timer_service fire_event, event_id=%s, event_type=%s, fire_at=%s",
        event_id,
        event.event_type,
        tostring(event.fire_at)
    )
    dispatch_event(event_id, event)
    return true
end

local function fetch_due_event_ids(now, limit)
    local event_ids = redis_call("zrangebyscore", _QUEUE_KEY, 0, now)
    if not event_ids or #event_ids == 0 then
        return {}
    end
    if limit and #event_ids > limit then
        local batch = {}
        for i = 1, limit do
            batch[i] = event_ids[i]
        end
        return batch
    end
    return event_ids
end

local function recover_overdue()
    local now = os.time()
    local total = 0
    while true do
        local event_ids = fetch_due_event_ids(now, const.timer.recover_batch)
        if #event_ids == 0 then
            break
        end
        for _, event_id in ipairs(event_ids) do
            fire_event(event_id)
            total = total + 1
        end
        skynet.sleep(0)
    end
    if total > 0 then
        logger.info("timer_service recover_overdue done, count=%s", total)
    end
    _RECOVERED = true
end

local function poll_loop()
    while true do
        if _RECOVERED then
            local now = os.time()
            local event_ids = fetch_due_event_ids(now, const.timer.recover_batch)
            for _, event_id in ipairs(event_ids) do
                fire_event(event_id)
            end
        end
        skynet.sleep(const.timer.poll_interval)
    end
end

function CMD.register(event_type, service_addr, cmd)
    if not event_type or event_type == "" then
        return false, "invalid event_type"
    end
    if not service_addr or not cmd or cmd == "" then
        return false, "invalid handler"
    end
    _HANDLERS[event_type] = {
        addr = service_addr,
        cmd = cmd,
    }
    logger.info("timer_service register, event_type=%s, cmd=%s", event_type, cmd)
    return true
end

function CMD.unregister(event_type)
    if not event_type then
        return false
    end
    _HANDLERS[event_type] = nil
    return true
end

function CMD.add(event_type, fire_at, payload, event_id)
    if not event_type or event_type == "" then
        return false, "invalid event_type"
    end
    fire_at = tonumber(fire_at)
    if not fire_at or fire_at <= 0 then
        return false, "invalid fire_at"
    end
    event_id = event_id or gen_event_id()
    local raw = serialize_event(event_type, payload, fire_at)
    redis_call("zadd", _QUEUE_KEY, event_id, fire_at)
    redis_call("hset", _DATA_KEY, event_id, raw)
    logger.info(
        "timer_service add, event_id=%s, event_type=%s, fire_at=%s",
        event_id,
        event_type,
        fire_at
    )
    return true, event_id
end

function CMD.cancel(event_id)
    if not event_id or event_id == "" then
        return false, "invalid event_id"
    end
    local score = redis_call("zscore", _QUEUE_KEY, event_id)
    if not score then
        return false, "event not found"
    end
    remove_event(event_id)
    logger.info("timer_service cancel, event_id=%s", event_id)
    return true
end

function CMD.get(event_id)
    if not event_id or event_id == "" then
        return nil
    end
    local raw = redis_call("hget", _DATA_KEY, event_id)
    local event = parse_event(raw)
    if not event then
        return nil
    end
    event.event_id = event_id
    event.fire_at = tonumber(redis_call("zscore", _QUEUE_KEY, event_id)) or event.fire_at
    return event
end

function CMD.reschedule(event_id, fire_at)
    fire_at = tonumber(fire_at)
    if not event_id or not fire_at or fire_at <= 0 then
        return false, "invalid args"
    end
    local raw = redis_call("hget", _DATA_KEY, event_id)
    local event = parse_event(raw)
    if not event then
        return false, "event not found"
    end
    event.fire_at = fire_at
    redis_call("zadd", _QUEUE_KEY, event_id, fire_at)
    redis_call("hset", _DATA_KEY, event_id, serialize_event(event.event_type, event.payload, fire_at))
    logger.info("timer_service reschedule, event_id=%s, fire_at=%s", event_id, fire_at)
    return true
end

function CMD.pending_count()
    return redis_call("zcard", _QUEUE_KEY) or 0
end

skynet.start(function()
    _SERVER_ID = skynet.getenv("server_id")
    _PROC_ID = skynet.getenv("proc_id")
    assert(_SERVER_ID and _PROC_ID, "timer_service missing server_id or proc_id")

    -- 有序集合
    _QUEUE_KEY = string.format(const.redis_key.timer_queue, _SERVER_ID, _PROC_ID)
    -- 哈希表
    _DATA_KEY = string.format(const.redis_key.timer_data, _SERVER_ID, _PROC_ID)

    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, CMD, cmd, ...)
    end)

    skynet.fork(function()
        recover_overdue()
        poll_loop()
    end)

    skynet.register(".timer_service")
    logger.info(
        "timer_service started, server_id=%s, proc_id=%s, queue_key=%s",
        _SERVER_ID,
        _PROC_ID,
        _QUEUE_KEY
    )
end)
