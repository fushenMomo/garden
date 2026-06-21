local skynet = require "skynet"

local logger = {}
local _LOG_SERVICE -- 日志服务地址

local _LOG_LEVEL_DICT = {
    ["DEBUG"] = 1,
    ["INFO"] = 2,
    ["WARN"] = 3,
    ["ERROR"] = 4,
}

-- 格式化日志消息
local function format_message(...)
    local n = select("#", ...)
    if n == 0 then
        return ""
    end

    if n > 1 then
        local fmt = select(1, ...)
        if type(fmt) == "string" then
            local args = { ... }
            local ok, formatted = pcall(string.format, fmt, table.unpack(args, 2, n))
            if ok then
                return formatted
            end
        end
    end

    local out = {}
    for i = 1, n do
        out[#out + 1] = tostring(select(i, ...))
    end
    return table.concat(out, " ")
end

local function get_log_service()
    if not _LOG_SERVICE then
        -- 启动进程日志唯一服务，用于记录日志 
        _LOG_SERVICE = skynet.uniqueservice("log_service")
    end
    return _LOG_SERVICE
end

local function write_log(level, ...)
    local level_value = _LOG_LEVEL_DICT[level] or 1
    local base_level_value = _LOG_LEVEL_DICT[skynet.getenv("logger_level") or "INFO"] or 1
    if level_value < base_level_value then
        return
    end
    local svc = get_log_service()
    local message = format_message(...)
    return skynet.call(svc, "lua", "write_log", level, message)
end

--@opt: 日志配置选项
function logger.init(opt)
    local cfg = opt or {}
    local svc = get_log_service()
    return skynet.call(svc, "lua", "start", cfg)
end

function logger.info(...)
    return write_log("INFO", ...)
end

function logger.debug(...)
    return write_log("DEBUG", ...)
end

function logger.warn(...)
    return write_log("WARN", ...)
end

function logger.error(...)
    return write_log("ERROR", ...)
end

return logger
