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

local _HOST = nil
local _REQUEST = nil

local PRINT_FLAG = ">"
local IS_BUSY = false
local IS_CONNECTING_FD = nil
local _READPACKAGE = nil
local _SESSION = 0

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

function CMD.selectServer(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    
    if (not req_data) or (#req_data < 1) then
        return nil, "invalid_request"
    end
    
    local server_id = req_data[1]
    local session = next_session()
    local req = _REQUEST("selectServer", {
        server_id = server_id,
    }, session)

    return IS_CONNECTING_FD, req, session
end

function CMD.joinGame(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end

    if (not req_data) or (#req_data < 2) then
        return nil, "invalid_request"
    end

    local acc_id = req_data[1]
    local token = req_data[2]
    local session = next_session()
    local req = _REQUEST("joinGame", {
        acc_id = acc_id,
        token = token,
    }, session)

    return IS_CONNECTING_FD, req, session
end

function CMD.heartbeatGame(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("heartbeatGame", {}, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.changeRoleName(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("changeRoleName", {
        new_name = req_data[1],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.createGuild(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("createGuild", {
        guild_name = req_data[1],
        guild_brief = req_data[2],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.getGuildList(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("getGuildList", {}, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.joinGuild(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("joinGuild", {
        guild_id = req_data[1],
    }, session)
    return IS_CONNECTING_FD, req, session
end

function CMD.changeGuildDesc(req_data)
    if not IS_CONNECTING_FD then
        return nil, "not_connected"
    end
    local session = next_session()
    local req = _REQUEST("changeGuildDesc", {
        guild_name = req_data[1],
        guild_brief = req_data[2],
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
end

local function dispatch_server_packet(pack)
    return _HOST:dispatch(pack)
end

local function recv_until_response(expected_session)
    while true do
        local ok_recv, pack = pcall(_READPACKAGE)
        if not ok_recv then
            return nil, "recv failed: " .. tostring(pack)
        end

        local ok_dispatch, t, a, b, c = pcall(dispatch_server_packet, pack)
        print("ok_dispatch:", ok_dispatch, t, a, b, c)
        if not ok_dispatch then
            return nil, "dispatch failed: " .. tostring(t)
        end

        if t == "REQUEST" then
            local name, args, response = a, b, c
            print("<---- push request:", name)
            if args and type(args) == "table" then
                print("    " .. util.serialize(args))
            end
            if type(response) == "function" then
                pcall(response)
            end
            if name == "kick_user" then
                print("server kick current user, connection closed.")
                reset_connection_state()
                return {
                    session = nil,
                    args = {
                        kicked = true,
                    },
                }
            end
        elseif t == "RESPONSE" then
            local session, args = a, b
            if expected_session == nil or expected_session == session then
                return {
                    session = session,
                    args = args,
                }
            end
        else
            return nil, "unknown package type: " .. tostring(t)
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
                -- 断开连接
                print("Bye.")
                reset_connection_state()
                io.write(PRINT_FLAG)
                io.stdout:flush()
            else
                if cmd and CMD[cmd] then
                    local fd, req, expected_session = CMD[cmd](rest)
                    if fd then
                        PRINT_FLAG = ">>"
                        if req then
                            send_packet(fd, req)

                            local resp, recv_err = recv_until_response(expected_session)
                            if not resp then
                                print(recv_err)
                                break
                            end

                            print("<---- response session:", resp.session)
                            if resp.args and type(resp.args) == "table" then
                                print("    " .. util.serialize(resp.args))
                            end
                        end
                    else
                        print("error: ", req)
                    end
                    io.write(PRINT_FLAG)
	                io.stdout:flush()
                elseif cmd then
                    print("Unknown command: " .. cmd)
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
                send_packet(IS_CONNECTING_FD, _REQUEST "heartbeatGame")
            end
			skynet.sleep(100 * 300)
		end
	end)

    skynet.timeout(10, function()
        skynet.fork(console_main_loop)
    end)
end)
