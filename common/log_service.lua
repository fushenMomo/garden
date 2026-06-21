local skynet = require "skynet"
require "skynet.manager"

local CMD = {}

local _STATE = {
    root_dir = "",
    files = {},
    source_modules = {},
}

--[[
sanitize_module 接口作用分析：

该接口负责对传入的 module 名称进行规范化（“清洗”）。
1. 先将任意传入参数转为字符串（module 为 nil 时使用 "default"）。
2. 将所有 "/" 替换为 "_"，避免路径符号干扰后续文件或目录操作。
3. 将非字母数字、下划线、短横线、点以外的字符都替换为 "_"，进一步提升兼容性和安全性。
4. 若最终得到的 module 名为空，则直接赋值为 "default"。

这样处理后的 module 名可以安全用作文件名、目录名，避免出现不合法或可疑的路径。
--]]
local function sanitize_module(module)
    module = tostring(module or "default")
    module = module:gsub("/", "_")
    module = module:gsub("[^%w_%-%.]", "_")
    if module == "" then
        module = "default"
    end
    return module
end

--[[
join_path 接口作用分析：

该接口用于拼接两个路径片段 a 和 b，确保二者之间只有一个斜杠分隔。
1. 如果 a 已经以斜杠结尾，则直接拼接 b；
2. 否则，在 a 末尾补充一个斜杠再拼接 b。
这样处理可避免多余斜杠或遗漏斜杠，确保得到规范的路径字符串。
--]]
local function join_path(a, b)
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

--[[
resolve_root_dir 接口作用分析：

该接口负责解析日志根目录。
1. 默认使用 "../log" 作为基础目录。
2. 如果传入的 opt 参数中包含 base_dir 字段，则使用 opt.base_dir 作为基础目录。
3. 获取当前节点名称，并进行规范化处理。
4. 返回规范化后的基础目录。
--]]
local function resolve_root_dir(opt)
    -- 默认使用 "../log" 作为基础目录。
    local base_dir = "../log"
    -- 如果传入的 opt 参数中包含 base_dir 字段，则使用 opt.base_dir 作为基础目录。
    if type(opt) == "table" and 
        type(opt.base_dir) == "string" and 
        opt.base_dir ~= "" then
        base_dir = opt.base_dir
        return base_dir
    end

    -- 获取当前节点名称，并进行规范化处理。
    local nodename = skynet.getenv("nodename") or "default"
    nodename = sanitize_module(nodename)
    -- 返回规范化后的基础目录。
    return join_path(base_dir, nodename)
end

--[[
ensure_dir 接口作用分析：

该接口用于确保指定路径的目录存在。
1. 如果传入的 path 为空或为 nil，则返回 false，并附带错误信息；
2. 否则，生成 shell 命令 'mkdir -p'，递归创建所需目录（若已存在不会报错）；
3. 使用 os.execute 执行目录创建命令；
4. 如果命令成功（返回 true 或 0），则返回 true，表示目录已存在或创建成功；
5. 否则返回 false，并附带失败信息。

该函数常用于日志、数据等需要动态创建目录的场合，保证路径可用。
--]]
local function ensure_dir(path)
    if path == nil or path == "" then
        return false, "empty path"
    end

    local cmd = string.format('mkdir -p "%s"', path)

    local ok = os.execute(cmd)
    if ok == true or ok == 0 then
        return true
    end
    return false, string.format("mkdir failed: %s", tostring(path))
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
    -- 如果缓存中存在，则直接返回文件句柄
    if cached and cached.fp then
        return cached.fp
    end

    if cached then
        -- 如果缓存中存在，则关闭文件句柄
        close_file(date_str)
    end
    
    -- 确保日志目录存在
    local ok, err = ensure_dir(_STATE.root_dir)
    if not ok then
        return nil, err
    end

    local path = join_path(_STATE.root_dir, date_str .. ".log")
    local fp, open_err = io.open(path, "a")
    if not fp then
        return nil, open_err
    end

    _STATE.files[date_str] = {
        fp = fp,
    }

    return fp
end

--[[
detect_module_by_source 接口作用分析：

该接口负责根据 source 地址确定其所属模块名，用于日志分类和溯源。

1. 检查 source 是否已在 source_modules 缓存表中，
    若有命中则直接返回缓存的模块名，避免重复查询。
2. 若缓存未命中，则通过 pcall(skynet.call, ".service", "lua", "LIST") 
    调用 skynet 服务管理器，获取所有服务名称和其地址的映射。
3. 遍历服务列表，通过 skynet.address(source) 比较，
    查找与当前 source 匹配的服务名，并赋值为 module。
4. 如果 module 为空或为空字符串，则使用 skynet.address(source) 的哈希值作为模块名。
5. 对 module 进行规范化处理，确保符合文件名和目录名规范。
6. 将 module 缓存到 source_modules 表中，以便后续复用。
7. 返回规范化后的模块名。
--]]
local function detect_module_by_source(source)
    local cached = _STATE.source_modules[source]
    if cached then
        return cached
    end

    local module
    -- 通过 pcall 安全调用 skynet.call，
    -- 向 ".service" 服务管理器发送 "lua" "LIST" 指令，
    -- 获取所有服务名与地址映射表
    local ok, service_list = pcall(skynet.call, ".service", "lua", "LIST")
    if ok and type(service_list) == "table" then
        local source_addr = skynet.address(source)
        for name, addr in pairs(service_list) do
            if addr == source_addr then
                module = name
                break
            end
        end
    end

    if module == nil or module == "" then
        module = string.format("addr_%s", skynet.address(source))
    end

    module = sanitize_module(module)
    _STATE.source_modules[source] = module
    return module
end

--@opt: 日志配置选项
function CMD.start(opt)
    -- 解析根目录
    _STATE.root_dir = resolve_root_dir(opt)

    local ok, err = ensure_dir(_STATE.root_dir)
    if not ok then
        return false, err
    end

    return true
end

function CMD.write_log(source, level, msg, ts)
    -- 解析日志来源的模块名，用于记录日志来源分类
    local safe_module = detect_module_by_source(source)
    local safe_level = string.upper(tostring(level or "INFO"))
    local safe_msg = tostring(msg or "")

    -- 获取当前时间戳，并转换为日期字符串
    local timestamp = tonumber(ts) or os.time()
    local date_str = os.date("%Y%m%d", timestamp)
    local time_str = os.date("%Y%m%d %H:%M:%S", timestamp)

    local fp, err = get_file(date_str)
    if not fp then
        --skynet.error(string.format("log_service open file failed: module=%s, err=%s", safe_module, tostring(err)))
        return false, err
    end

    local line = string.format("[%s] [%s] [%s] %s\n", time_str, safe_level, safe_module, safe_msg)
    local ok, write_err = fp:write(line)
    if not ok then
        close_file(date_str)
        --skynet.error(string.format("log_service write failed: module=%s, err=%s", safe_module, tostring(write_err)))
        return false, write_err
    end
    fp:flush()
    return true
end

function CMD.stop()
    for date_key in pairs(_STATE.files) do
        close_file(date_key)
    end
    skynet.exit()
end

skynet.start(function()
    -- 在此处，source参数表示消息发送方的服务地址（即发送者的skynet地址），用于标识调用该服务的上游skynet服务源头
    skynet.dispatch("lua", function(session, source, cmd, ...)
        --skynet.trace("log_service dispatch")
        --skynet.error(string.format("log_service dispatch: session=%s, source=%s, cmd=%s, ...", tostring(session), tostring(source), tostring(cmd), tostring(...)))
        local f = CMD[cmd]
        if not f then
            error(string.format("Unknown CMD %s", tostring(cmd)))
        end

        local ok, r1, r2
        if cmd == "write_log" then
            ok, r1, r2 = pcall(f, source, ...)
        else
            ok, r1, r2 = pcall(f, ...)
        end

        if not ok then
            if session ~= 0 then
                -- 失败情况的返回
                skynet.retpack(false, r1)
            end
            return
        end

        if session ~= 0 then
            -- 这句代码的意思是：将命令处理函数的返回结果r1和r2打包响应回请求方。
            -- skynet.retpack用于将返回值按照skynet的rpc协议打包返回给调用者。如果session不为0，表示这是一个有响应的请求，需要返回结果。
            skynet.retpack(r1, r2)
        end
    end)

    skynet.register(".log_service")
end)
