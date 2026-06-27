local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"

local util = require "common.util"
local socket = require "client.socket"

local proto = require "common.proto"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local sharedata = require "skynet.sharedata"
local const = nil
local _CLIENT_HEARTBEAT_INTERVAL_TIME = 15 -- 15秒

local _HOST = nil
local _REQUEST = nil

local PRINT_FLAG = ">"
local IS_BUSY = false
local IS_CONNECTING_FD = nil
local _READPACKAGE = nil
local _RECV_LAST = ""
local _SESSION = 0
local _WAIT_RESPONSE = {}

local CMD = {}
local reconnect

local function next_session()
    _SESSION = _SESSION + 1
    return _SESSION
end

local function send_packet(fd, body)
	-- 参数校验，body 必须是字符串类型
    if not fd then
        return nil, "fd_is_empty"
    end
	if type(body) ~= "string" then
		return nil, "body_not_string"
	end
	-- 按照大端序打包 body，前2字节为长度
	-- string.pack(">s2", body) 的作用是将 body 串以长度为前2字节（大端序）的方式
	-- 进行二进制打包，生成的结果前2字节是 body 的长度，后面跟着 body 的内容，
	-- 大端序：高位在前，低位在后，小端序：低位在前，高位在后
	local pack = string.pack(">s2", body)
	-- 通过 socket 发送二进制包
	socket.send(fd, pack)
	return true
end


function CMD.connect(req_data)
    if not req_data or #req_data < 1 then
        return nil, "invalid_request"
    end
    local host = "127.0.0.1"
    local port = req_data[1]
    local fd, err = reconnect(host, port)
    if not fd then
        return nil, err
    end
    return fd, nil
end

function CMD.register(req_data)
    --logger.info("register request: %s", util.serialize(req_data))
    print("register request: ", type(req_data), util.serialize(req_data))
    if (not req_data) or (#req_data < 3) then
        return nil, "invalid_request"
    end
    local host = "127.0.0.1"
    local port = req_data[1]
    local user = req_data[2]
    local pass = req_data[3]
    local platform = const.login_type.default
    local fd, err = reconnect(host, port)
    if not fd then
        return nil, err
    end

    local session = next_session()
    local req = _REQUEST("register", {
        account_name = user,
        password = pass,
        platform = platform,
    }, session)

    return fd, req, session
end

function CMD.login(req_data)
    if (not req_data) or (#req_data < 3) then
        return nil, "invalid_request"
    end
    local host = "127.0.0.1"
    local port = req_data[1]
    local user = req_data[2]
    local pass = req_data[3]
    local platform = const.login_type.default
    local fd, err = reconnect(host, port)
    if not fd then
        return nil, err
    end

    local session = next_session()
    local req = _REQUEST("login", {
        account_name = user,
        password = pass,
        platform = platform,
    }, session)

    return fd, req, session
end

function CMD.select_server(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    
    if (not req_data) or (#req_data < 1) then
        return nil, "invalid_request"
    end
    
    local server_id = req_data[1]
    local session = next_session()
    local req = _REQUEST("select_server", {
        server_id = server_id,
    }, session)

    return IS_CONNECTING_FD, req, session
end

function CMD.join_game(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end

    if (not req_data) or (#req_data < 2) then
        return nil, "invalid_request"
    end

    local acc_id = req_data[1]
    local token = req_data[2]
    local session = next_session()
    local req = _REQUEST("join_game", {
        acc_id = acc_id,
        token = token,
    }, session)

    return IS_CONNECTING_FD, req, session
end

function CMD.heartbeat_game(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("heartbeat_game", {}, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.change_role_name(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("change_role_name", {
        new_name = req_data[1],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.create_guild(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("create_guild", {
        guild_name = req_data[1],
        guild_brief = req_data[2],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.get_guild_list(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("get_guild_list", {}, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.join_guild(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("join_guild", {
        guild_id = req_data[1],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.change_guild_desc(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("change_guild_desc", {
        guild_name = req_data[1],
        guild_brief = req_data[2],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.gain_item(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("gain_item", {
        item_id = req_data[1],
        item_count = req_data[2],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.cost_item(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("cost_item", {
        item_id = req_data[1],
        item_count = req_data[2],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.active_partner(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("active_partner", {
        partner_id = req_data[1],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.receive_task_reward(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("receive_task_reward", {
        task_index = req_data[1],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.show_world_agent_data(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    if (not req_data) or (#req_data < 2) then
        return nil, "invalid_request"
    end
    local session = next_session()
    local req = _REQUEST("show_world_agent_data", {
        module_desc = req_data[1],
        data_desc = req_data[2],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.start_fight(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("start_fight", {
        fight_type = req_data[1],
        server_id = req_data[2],
        fight_dbid = req_data[3],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.end_fight(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("end_fight", {
        fight_type = req_data[1],
        battle_id = req_data[2],
    }, session)
    return IS_CONNECTING_FD, req, session
end

skynet.init(function()
	logger.info("Console server initialized")
end)

--@line
local function parse_request(line)
    if (not line) or (line == "") then
        return nil, "empty_input"
    end

    local parts = {}
    for word in line:gmatch("%S+") do
        parts[#parts + 1] = word
    end

    if #parts == 0 then
        return nil, "empty_input"
    end

    local cmd = parts[1]
    local rest = {}
    for i = 2, #parts do
        rest[#rest + 1] = parts[i]
    end

    return cmd, rest
end

local function read_line()
    -- 在 skynet 服务里不要用 io.read，会阻塞 worker 线程并触发 endless loop 告警ss
    local line = socket.readstdin()
    if line == nil or line == "" then
        return nil
    end
    local cmd, rest = parse_request(line)
    print("cmd:", cmd, "rest:", rest)
    return cmd, rest
end

local function unpack_f(fd, f)
	local last = ""

	local function try_recv()
		local result
		result, last = f(last)
		if result then
			return result
		end
		local r = socket.recv(fd)
		if not r then
			return nil
		end
		if r == "" then
			error("server closed")
		end
		result, last = f(last .. r)
		return result
	end

	return function()
		while true do
			local result = try_recv()
			if result then
				return result
			end
			socket.usleep(100)
		end
	end
end

local function unpack_packet(text)
	local size = string.len(text)
	if size < 2 then
		return nil, text
	end
	-- 解释：text:byte(1) 返回字符串 text 的第1个字节（即首字节）的数值，text:byte(2) 返回第2个字节的数值。
	-- 由于协议规定前2字节为包体长度（大端序，高位在前），
	-- 所以 s = (第1字节 * 256) + 第2字节，拼合还原出包体实际长度数值。
	local s = text:byte(1) * 256 + text:byte(2)
	if size < s + 2 then
		return nil, text
	end
	-- 若已解析出完整包体，则返回：
	-- 包体字符串（text:sub(3,2+s)），和剩余待处理的数据（text:sub(3+s)）
	--return text:sub(3, 2 + s), text:sub(3 + s)
	return string.sub(text, 3, 2+s), string.sub(text, 3+s)
end

reconnect = function(host, port)
    if IS_CONNECTING_FD then
        return IS_CONNECTING_FD
    end
    IS_CONNECTING_FD = socket.connect(host, port)
    if not IS_CONNECTING_FD then
        _READPACKAGE = nil
        return nil, "connect_failed"
    end
    _READPACKAGE = unpack_f(IS_CONNECTING_FD, unpack_packet)
    _RECV_LAST = ""
    return IS_CONNECTING_FD
end

local function one_line_table(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = t[k]
		parts[#parts + 1] = string.format("%s=%s", k, tostring(v))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function reset_connection_state()
    if IS_CONNECTING_FD then
        socket.close(IS_CONNECTING_FD)
    end
    PRINT_FLAG = ">"
    IS_CONNECTING_FD = nil
    _READPACKAGE = nil
    _RECV_LAST = ""
    for _, entry in pairs(_WAIT_RESPONSE) do
        if not entry.result then
            entry.err = "connection closed"
        end
        skynet.wakeup(entry.co)
    end
    _WAIT_RESPONSE = {}
end

local function try_read_one_package()
    if not IS_CONNECTING_FD then
        return nil
    end
    local result
    result, _RECV_LAST = unpack_packet(_RECV_LAST)
    if result then
        return result
    end
    local r = socket.recv(IS_CONNECTING_FD)
    if not r then
        return nil
    end
    if r == "" then
        error("server closed")
    end
    result, _RECV_LAST = unpack_packet(_RECV_LAST .. r)
    return result
end

local function dispatch_server_packet(pack)
    return _HOST:dispatch(pack)
end

local _prompt_gen = 0

local function cancel_deferred_prompt()
    _prompt_gen = _prompt_gen + 1
end

local function write_prompt()
    cancel_deferred_prompt()
    io.write("\n" .. PRINT_FLAG)
    io.stdout:flush()
end

local function defer_prompt()
    cancel_deferred_prompt()
    local gen = _prompt_gen
    skynet.timeout(5, function()
        if gen == _prompt_gen then
            io.write("\n" .. PRINT_FLAG)
            io.stdout:flush()
        end
    end)
end

local function flush_prompt()
    cancel_deferred_prompt()
    io.write("\n" .. PRINT_FLAG)
    io.stdout:flush()
end

local function show_history(max_n)
    max_n = max_n or 20
    local path = (os.getenv("HOME") or ".") .. "/.mirage_console_history"
    local f = io.open(path, "r")
    if not f then
        print("no history: " .. path)
        return
    end
    local lines = {}
    for line in f:lines() do
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    f:close()
    local start = math.max(1, #lines - max_n + 1)
    for i = start, #lines do
        print(string.format("%4d  %s", i, lines[i]))
    end
end

local function handle_server_push(name, args, response)
    print("<---- push request:", name)
    if args and type(args) == "table" then
        print("    " .. util.serialize(args))
    end
    if type(response) == "function" then
        pcall(response)
    end
    if name == "kick_user" then
        print("server kick current user, connection closed.")
        for _, entry in pairs(_WAIT_RESPONSE) do
            entry.result = {
                session = nil,
                args = { kicked = true },
            }
        end
        reset_connection_state()
    end
end

local function wait_response(expected_session, send_fn)
    local co = coroutine.running()
    local entry = { co = co }
    _WAIT_RESPONSE[expected_session] = entry
    if send_fn then
        send_fn()
    end
    skynet.wait(co)
    _WAIT_RESPONSE[expected_session] = nil
    if entry.err then
        return nil, entry.err
    end
    return entry.result
end

local function recv_loop()
    while true do
        if not IS_CONNECTING_FD then
            skynet.sleep(10)
        else
            local ok_recv, pack = pcall(try_read_one_package)
            if not ok_recv then
                reset_connection_state()
            elseif pack then
                local ok_dispatch, t, a, b, c = pcall(dispatch_server_packet, pack)
                if ok_dispatch then
                    if t == "REQUEST" then
                        handle_server_push(a, b, c)
                        flush_prompt()
                    elseif t == "RESPONSE" then
                        local session, args = a, b
                        local entry = _WAIT_RESPONSE[session]
                        if entry then
                            entry.result = { session = session, args = args }
                            skynet.wakeup(entry.co)
                        else
                            print("<---- response session:", session)
                            if args and type(args) == "table" then
                                print("    " .. util.serialize(args))
                            end
                            flush_prompt()
                        end
                    end
                end
                skynet.yield()
            else
                skynet.sleep(1)
            end
        end
    end
end


local function console_main_loop()
    print("...> Please input your command:")
    io.write(PRINT_FLAG)
    io.stdout:flush()
    while true do
        if not IS_BUSY then
            IS_BUSY = true

            local cmd, rest = read_line()
            if IS_CONNECTING_FD and cmd == "quit" then
                print("Bye.")
                reset_connection_state()
                write_prompt()
            elseif cmd == "history" then
                show_history(tonumber(rest and rest[1]))
                write_prompt()
            else
                if cmd and CMD[cmd] then
                    local fd, req, expected_session = CMD[cmd](rest)
                    if fd then
                        if req then
                            local resp, recv_err = wait_response(expected_session, function()
                                send_packet(fd, req)
                            end)
                            if not resp then
                                print(recv_err)
                                break
                            end

                            print("<---- response session:", resp.session)
                            if resp.args and type(resp.args) == "table" then
                                print("    " .. util.serialize(resp.args))
                            end
                            if cmd == "login" or cmd == "register" or cmd == "join_game" then
                                if resp.args and resp.args.error_code == const.error_code.success then
                                    PRINT_FLAG = ">>"
                                else
                                    PRINT_FLAG = ">"
                                end
                            else
                                PRINT_FLAG = ">>"
                            end
                            defer_prompt()
                        else
                            if cmd == "connect" then
                                PRINT_FLAG = ">>"
                            end
                            write_prompt()
                        end
                    else
                        print("error: ", req)
                        write_prompt()
                    end
                elseif cmd then
                    print("Unknown command: " .. cmd)
                    write_prompt()
                end
                
            end
            IS_BUSY = false
        end
        skynet.sleep(100)
    end
    
end

skynet.start(function()
	-- 启动配置管理服务，用于管理配置文件
	skynet.uniqueservice("config_mgr")
    -- config_mgr 在 init 中写入 sharedata，等它启动完成后再 query，避免启动时序竞态
    const = sharedata.query "const"
    -- 启动协议加载服务
	skynet.uniqueservice("protoloader")
	-- 初始化业务日志记录器
	logger.init()
	logger.info("business logger initialized")
    -- 加载协议
    _HOST = sprotoloader.load(2):host "package"
    
	-- _REQUEST在这里的作用是绑定协议解析器，用于解包客户端发送过来的请求
	-- _HOST:attach 返回的对象包含了解析请求的能力，一般用作服务端sproto协议的解析入口
	_REQUEST = _HOST:attach(sprotoloader.load(1))
	skynet.register(".console")
    skynet.fork(function()
		while true do
            if IS_CONNECTING_FD then
                send_packet(IS_CONNECTING_FD, _REQUEST "heartbeat_game")
            end
			skynet.sleep(100 * _CLIENT_HEARTBEAT_INTERVAL_TIME)
		end
	end)

    skynet.fork(recv_loop)
    skynet.timeout(10, function()
        skynet.fork(console_main_loop)
    end)
end)
