local skynet = require "skynet"
local socket = require "skynet.socket"
local json_min = require "common.json_min"
local logger = require "common.logger"
local util = require "common.util"
local cluster = require "skynet.cluster"

--local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local _HOST = nil
local _SEND_REQUEST = nil

local _WATCHDOG
local _GATE
local _CLIENT_FD
local _ACCOUNT_SERVICE
local _SERVER_LIST_SERVICE
local _ACC_ID = 0
local _TOKEN = ""
local _LAST_SERVER_ID = 0

local sharedata = require "skynet.sharedata"
local const

-- 登录服的agent
local REQUEST = {}
local CMD = {}

local function request(name, args, response)
	local f = assert(REQUEST[name])
	local r = f(args)
	if response then
		return response(r)
	end
end

local function send_package(payload)
	local pack = string.pack(">s2", payload)
	socket.write(_CLIENT_FD, pack)
end

function REQUEST:heartbeat()
	logger.info("heartbeat request, acc_id: %s", _ACC_ID)
	local ok, error_code = pcall(skynet.call, _ACCOUNT_SERVICE, "lua", "heartbeat", _ACC_ID)
	return { error_code = error_code, server_time = os.time() }
end

function REQUEST:register()
	local user = self.account_name
	local pass = self.password
	local platform = self.platform
	local error_code, acc_id = skynet.call(
											_ACCOUNT_SERVICE, 
											"lua", 
											"register", 
											user, 
											pass,
											platform
										)
	_ACC_ID = acc_id or 0
	return { error_code = error_code, account_name = user, acc_id = acc_id or 0 }
end

function REQUEST:login()
	local user = self.account_name
	local pass = self.password
	local platform = self.platform
	local error_code, acc_id, token = skynet.call(
													_ACCOUNT_SERVICE, 
													"lua", 
													"login", 
													user, 
													pass,
													platform
												)
	if error_code ~= const.error_code.success then
		return {
			error_code = error_code,
			account_name = user,
			acc_id = 0,
			server_list = {},
			token = "",
			last_server_id = 0
		}
	end
	_ACC_ID = acc_id or 0
	local server_info_list = skynet.call(
											_SERVER_LIST_SERVICE, 
											"lua", 
											"get_server_info_list"
										)
	local server_list = {}
	if server_info_list then
		for _, server_info in ipairs(server_info_list) do
			server_info.server_id = server_info.id
			server_info.server_num = server_info.num
			server_info.server_name = server_info.name
			server_info.server_state = server_info.state
			server_info.server_flag = server_info.flag
			table.insert(server_list, server_info)
		end
	end

	_TOKEN = token

	local ret, result = skynet.call(".sk_login", "lua", "select_one_by_key", "login_info", "act_id", acc_id)
	if ret and result then
		_LAST_SERVER_ID = result.last_server_id or 0
	end

	return { 
			error_code = error_code, 
			account_name = user, 
			acc_id = acc_id or 0, 
			server_list = server_list,
			token = token,
			last_server_id = _LAST_SERVER_ID
		}
end


--@server_id
local function generate_gateway_proc_id(server_id)
	local server_info = skynet.call(_WATCHDOG, "lua", "get_server_info", server_id)
	logger.info("generate_gateway_proc_id, server_id: %s, server_info: %s", server_id, util.serialize(server_info))
	if not server_info then
		return
	end
	if not next(server_info) then
		return
	end
	local dst_proc_id = nil
	local dst_proc_info = nil
	for proc_id, info in pairs(server_info) do
		if not dst_proc_id then
			dst_proc_id = proc_id
			dst_proc_info = info
		else
			if dst_proc_info and (dst_proc_info.client_count > info.client_count) then
				dst_proc_id = proc_id
				dst_proc_info = info
			end
		end
	end
	return dst_proc_id, dst_proc_info
end


function REQUEST:selectServer()
	local server_id = tonumber(self.server_id) or 0
	local server_info = skynet.call(_WATCHDOG, "lua", "get_server_info", server_id)
	logger.info("selectServer request, server_id=%s, server_info=%s", server_id, util.serialize(server_info))
	if not server_info then
		return {
				error_code = const.error_code.server_not_found,
				server_id = server_id,
				server_host = "",
				server_port = 0
			}
	end
	local proc_id, info = generate_gateway_proc_id(server_id)
	if not info then
		return {
				error_code = const.error_code.server_not_found,
				server_id = server_id,
				server_host = "",
				server_port = 0
			}
	end

	if _LAST_SERVER_ID ~= server_id then
		local ret = skynet.call(".sk_login", "lua", "update", "login_info", "act_id", _ACC_ID, {last_server_id = server_id})
		if not ret then
			logger.error("selectServer update last_server_id failed, server_id: %s, acc_id: %s", server_id, _ACC_ID)
		else
			_LAST_SERVER_ID = server_id
		end
	end


	-- 同步session信息到gateway --- proc_id
	local dest_addr = string.format("gateway_%s_%s", server_id, proc_id)
	local ret = cluster.call(dest_addr, ".handle_message", "sync_login_agent_session_info", _ACC_ID, _TOKEN)
	if not ret then
		logger.error("sync_session_info to gateway failed, server_id: %s, proc_id: %s", server_id, proc_id)
	end

	return {
			error_code = const.error_code.success,
			server_id = server_id,
			server_host = info.host or "127.0.0.1",
			server_port = info.port or 0
		}
end

skynet.register_protocol({
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		-- 这里 _HOST:dispatch(msg, sz) 的作用是将客户端发送过来的数据包（msg, sz）解包并分发处理。
		-- _HOST 是由 sprotoloader.load(1):host "package" 得到的 sproto host 对象，
		-- 它包含了客户端协议的解包和调度逻辑。
		-- 该方法会解析协议包，返回请求类型、名称、数据体等信息，供后续 dispatch 逻辑使用。
		return _HOST:dispatch(msg, sz)
	end,
	dispatch = function (fd, _, type, ...)
		assert(fd == _CLIENT_FD)	-- You can use fd to reply message
		skynet.ignoreret()	-- session is fd, don't call skynet.ret
		skynet.trace()
		if type == "REQUEST" then
			local ok, result  = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				skynet.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "login_agent doesn't support request client"
		end
	end,
})

function CMD.start(conf)
	local fd = conf.client
	_GATE = conf.gate
	_WATCHDOG = conf.watchdog
	_CLIENT_FD = fd
	-- 这里通过 skynet.address 查询并保存全局唯一服务的地址。
	-- .account_service 和 .server_list_service 是在 login_main.lua 中通过 skynet.register 注册的服务名，
	-- 因此可以直接用 skynet.address 查找其 skynet 地址。
	_ACCOUNT_SERVICE =  skynet.address ".account_service"
	_SERVER_LIST_SERVICE =  skynet.address ".server_list_service"
	_PACKAGE_MAX = tonumber(skynet.getenv("login_package_max")) or 8192

	--[[
	在sproto中，host对象是用来处理协议的解包和打包的。
	它包含了协议的定义和处理逻辑，可以方便地进行协议的解析和打包。
	_HOST = sprotoloader.load(1):host "package" 用 c2s 作为 host（解析客户端来的包）
	_HOST:attach(sprotoloader.load(2)) 把 s2c 挂上去用于服务端发包（比如你的 heartbeat）
	--]]
	_HOST = sprotoloader.load(1):host "package"
	_SEND_REQUEST = _HOST:attach(sprotoloader.load(2))
	--[[
	skynet.fork(function()
		while true do
			send_package(_SEND_REQUEST "heartbeat")
			skynet.sleep(500)
		end
	end)
	--]]
	
	-- 这句代码的作用是通知网关（GATE）将指定的客户端连接 fd 
	-- 转发给当前的 login_agent 进行后续和客户端的数据通信，
	-- 即让网关把对应 fd 的数据通过 skynet 框架转发到本服务。
	-- 这样客户端后续的请求消息会发送到本 agent 服务处理。
	skynet.call(_GATE, "lua", "forward", fd)
	-- skynet.redirect(agent, c.client, "client", fd, msg, sz)
end

function CMD.disconnect()
	if  _SEND_REQUEST  then
		send_package(_SEND_REQUEST("kick_user", {}))
	end
	skynet.exit()
end

function CMD.check_timeout()
	if _ACC_ID ~= 0 then
		local ok, is_timeout = pcall(skynet.call, _ACCOUNT_SERVICE, "lua", "check_timeout", _ACC_ID)
		if ok then
			if is_timeout then
				return true
			end
		end
	end
	return false
end

skynet.init(function()
	const = sharedata.query "const"
end)

skynet.start(function()
	-- 注册一个 Lua 协议处理器，用于处理来自网关的消息。
	skynet.dispatch("lua", function(_, _, command, ...)
		-- skynet.trace() 这行代码是用于调试的，它会在控制台输出当前的调用栈信息。
		-- 这可以帮助开发者更好地理解代码的执行流程，特别是在需要调试复杂的逻辑时。
		-- 在生产环境中，通常会关闭这个调试功能，以提高性能。
		skynet.trace("login_agent_dispatch")
		local f = assert(CMD[command])
		skynet.ret(skynet.pack(f(...)))
	end)
end)
