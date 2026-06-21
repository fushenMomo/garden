local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local snutil = require "common.snutil"
local DBDef = require "common.db_keys_define"
local row_cache = require "common.row_cache"
local data_access = require "common.data_access"
local util = require "common.util"

local FLUSH_INTERVAL = 100 * 5 -- 1s
local MAX_COUNT = 100

local CMD = {}


function CMD.flush_row(element)
    element = util.unserialize(element)
    if not element then
       return false
    end
    local row_key = element.row_key
    local cached = element.cached
    local changed_fields = element.changed_fields

    local table_def = DBDef.parse_table_def_by_row_key(row_key)
    if not table_def then
        logger.error("data_sync flush_row unknown row_key=%s", row_key)
        return false
    end

    local ok = data_access.update_to_mysql(table_def, cached, changed_fields)

    if not ok then
        logger.error("data_sync flush_row failed, row_key=%s", row_key)
        return false
    end
    return true
end


local function backup()
    local nlen = row_cache.get_dirty_queue_len()
    if nlen <= 0 then
        return
    end
    if nlen > MAX_COUNT then
        nlen = MAX_COUNT
    end
    
    local count = 0
    local element = row_cache.pop_dirty_row_key()
    while element do
        if CMD.flush_row(element) then
            count = count + 1
        end
        if count >= nlen then
            break
        else
            element = row_cache.pop_dirty_row_key()
        end
    end
end

local function flush_loop()
    while true do
        backup()
        skynet.sleep(FLUSH_INTERVAL)
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, _, cmd, ...)
        snutil.lua_docmd(session, CMD, cmd, ...)
    end)
    skynet.fork(flush_loop)
    skynet.register(".data_sync")
    logger.info("data_sync service started")
end)
