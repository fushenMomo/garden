local skynet = require "skynet"
local util = require "common.util"

local M = {}

local _STATE = {
    root_dir = "",
    files = {},
}

local function join_path(a, b)
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

local function ensure_dir(path)
    if path == nil or path == "" then
        return false, "empty path"
    end
    local ok = os.execute(string.format('mkdir -p "%s"', path))
    if ok == true or ok == 0 then
        return true
    end
    return false, string.format("mkdir failed: %s", path)
end

local function close_file(date_key)
    local cached = _STATE.files[date_key]
    if not cached then
        return
    end
    if cached.fp then
        cached.fp:close()
    end
    _STATE.files[date_key] = nil
end

local function get_file(date_str)
    local cached = _STATE.files[date_str]
    if cached and cached.fp then
        return cached.fp
    end
    if cached then
        close_file(date_str)
    end
    local ok, err = ensure_dir(_STATE.root_dir)
    if not ok then
        return nil, err
    end
    local path = join_path(_STATE.root_dir, date_str .. ".log")
    local fp, open_err = io.open(path, "a")
    if not fp then
        return nil, open_err
    end
    _STATE.files[date_str] = { fp = fp }
    return fp
end

local function init_root_dir()
    local server_id = skynet.getenv("server_id") or "0"
    _STATE.root_dir = string.format("../log/trace_log_%s", tostring(server_id))
    ensure_dir(_STATE.root_dir)
end

init_root_dir()

function M.handle(entry)
    local ts = tonumber(entry.ts) or os.time()
    local date_str = os.date("%Y%m%d", ts)
    local time_str = os.date("%Y%m%d %H:%M:%S", ts)
    local source = tostring(entry.source or "")
    local data_str = util.serialize(entry.data or {})

    local fp, err = get_file(date_str)
    if not fp then
        return false, err
    end

    local line = string.format("[%s] [%s] %s\n", time_str, source, data_str)
    local ok, write_err = fp:write(line)
    if not ok then
        close_file(date_str)
        return false, write_err
    end
    fp:flush()
    return true
end

return M
