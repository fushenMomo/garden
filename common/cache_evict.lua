local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local const = require "common.const"
local data_access = require "common.data_access"

local function scan_interval_centisecond()
    return const.cache_evict.scan_interval_hours * 3600 * 100
end

local function scan_once()
    local server_id = tonumber(skynet.getenv("server_id"))
    local idle_seconds = const.cache_evict.idle_hours * 3600
    local cutoff = os.time() - idle_seconds
    local batch_size = const.cache_evict.batch_size or 100

    local candidates = data_access.query_stale_login_players(server_id, cutoff)
    if not candidates or #candidates == 0 then
        logger.info("cache_evict scan_once, no candidates, server_id=%s, cutoff=%s", server_id, cutoff)
        return
    end

    local stats = {
        total = #candidates,
        ok = 0,
        online = 0,
        no_cache = 0,
        --flush_failed = 0,
    }

    for i, act_id in ipairs(candidates) do
        act_id = tonumber(act_id) or act_id
        local result = data_access.evict_player_cache(server_id, act_id)
        if stats[result] ~= nil then
            stats[result] = stats[result] + 1
        end

        if i % batch_size == 0 then
            skynet.sleep(1)
        end
    end

    logger.info(
        "cache_evict scan_once done, server_id=%s, total=%s, ok=%s, online=%s, no_cache=%s, flush_failed=%s",
        server_id,
        stats.total,
        stats.ok,
        stats.online,
        stats.no_cache,
        stats.flush_failed
    )
end

local function evict_loop()
    while true do
        local ok, err = pcall(scan_once)
        if not ok then
            logger.error("cache_evict scan_once error, err=%s", err)
        end
        skynet.sleep(scan_interval_centisecond())
    end
end

skynet.start(function()
    skynet.fork(evict_loop)
    skynet.register(".cache_evict")
    logger.info(
        "cache_evict service started, scan_interval_hours=%s, idle_hours=%s",
        const.cache_evict.scan_interval_hours,
        const.cache_evict.idle_hours
    )
end)
