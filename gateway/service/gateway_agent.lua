local skynet = require "skynet"
local socket = require "skynet.socket"
local logger = require "common.logger"
local sharedata = require "skynet.sharedata"
local cluster = require "skynet.cluster"
local util = require "common.util"

local sprotoloader = require "sprotoloader"

local _GATE
local _CLIENT_FD
local _WATCHDOG
local _ENTITY_ID
local _IN_GAME = false
local _WORLD_CLUSTER_NAME = nil

local _HOST = nil
local _SEND_REQUEST = nil

local const

-- gateway 本地处理的协议（进服前/网关专属）
local REQUEST = {}
local CMD = {}

local function send_package(payload)
	local pack = string.pack(">s2", payload)
	socket.write(_CLIENT_FD, pack)
end

local function get_entity_id()
	return _ENTITY_ID
end

local function forward_to_world(name, args, response)
	if not _IN_GAME or not _WORLD_CLUSTER_NAME then
		return response({ error_code = const.error_code.not_in_game })
	end
	local ok, result = pcall(
		cluster.call,
		_WORLD_CLUSTER_NAME,
		".handle_message",
		"client_request",
		_ENTITY_ID,
		name,
		args
	)
	if not ok then
		logger.error("forward_to_world failed, name=%s, err=%s", name, result)
		return response({ error_code = const.error_code.world_request_failed })
	end
	return response and response(result)
end

local function request(name, args, response)
	local f = REQUEST[name]
	if f then
		local r = f(args)
		if response then
			return response(r)
		end
		return
	end
	return forward_to_world(name, args, response)
end

function REQUEST:join_game()
	local acc_id = tonumber(self.acc_id)
	local token = self.token
	logger.info("joinGame request, acc_id=%s, token=%s", acc_id, token)

	local handle_message_address = skynet.address(".handle_message")
	local ret = skynet.call(handle_message_address, "lua", "check_agent_login", acc_id, token)
	if not ret then
		return {error_code = const.error_code.join_game_time_out}
	end

	-- 登录成功之后，同步消息到world服 --------------------------------------
	local server_id = skynet.getenv("server_id")
	local cur_dest_world_proc_id = skynet.call(handle_message_address, "lua", "get_cur_open_world_proc")
	local dest_cluster_name = "world" .. "_" .. server_id .. "_" .. cur_dest_world_proc_id
	logger.info("joinGame request, server_id=%s, cur_dest_world_proc_id=%s, dest_cluster_name=%s",
		server_id, cur_dest_world_proc_id, dest_cluster_name)
	local msg = {
		acc_id = acc_id,
		gateway_proc_id = skynet.getenv("proc_id"),
		entity_id = get_entity_id(),
	}
	local login_ret = cluster.call(
		dest_cluster_name,
		".handle_message",
		"account_login_world",
		msg
	)
	if not login_ret or not login_ret.success then
		return {error_code = const.error_code.join_game_world_failed}
	end

	_WORLD_CLUSTER_NAME = login_ret.world_cluster_name
	_IN_GAME = true
	logger.info("joinGame success, entity_id=%s, world_cluster_name=%s", _ENTITY_ID, _WORLD_CLUSTER_NAME)

	local ret1 = skynet.call(handle_message_address, "lua", "remove_login_session_info", acc_id)
	if not ret1 then
		logger.error("joinGame request, remove_login_session_info failed, acc_id=%s", acc_id)
	end

	return {error_code = const.error_code.success}
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
		assert(fd == _CLIENT_FD)
		skynet.ignoreret()
		if type == "REQUEST" then
			local ok, result = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				skynet.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "gateway_agent doesn't support request client"
		end
	end,
})

function CMD.disconnect()
	if _IN_GAME and _WORLD_CLUSTER_NAME and _ENTITY_ID then
		pcall(cluster.send, _WORLD_CLUSTER_NAME, ".handle_message", "player_disconnect", _ENTITY_ID)
	end
	if _SEND_REQUEST then
		send_package(_SEND_REQUEST("kick_user", {}))
	end
	skynet.exit()
end

function CMD.start(conf)
	local fd = conf.client
	_GATE = conf.gate
	_WATCHDOG = conf.watchdog
	_CLIENT_FD = fd

	--[[
	在sproto中，host对象是用来处理协议的解包和打包的。
	它包含了协议的定义和处理逻辑，可以方便地进行协议的解析和打包。
	_HOST = sprotoloader.load(1):host "package" 用 c2s 作为 host（解析客户端来的包）
	_HOST:attach(sprotoloader.load(2)) 把 s2c 挂上去用于服务端发包（比如你的 heartbeat）
	--]]
	_HOST = sprotoloader.load(1):host "package"
	_SEND_REQUEST = _HOST:attach(sprotoloader.load(2))

	-- 这句代码的作用是通知网关（GATE）将指定的客户端连接 fd 
	-- 转发给当前的 gateway_agent 进行后续和客户端的数据通信，
	-- 即让网关把对应 fd 的数据通过 skynet 框架转发到本服务。
	-- 这样客户端后续的请求消息会发送到本 agent 服务处理。
	skynet.call(_GATE, "lua", "forward", fd)
	return _ENTITY_ID
end

function CMD.push_to_client(proto, data)
	if not _SEND_REQUEST then
		return false
	end
	logger.info("push_to_client, entity_id=%s, proto=%s, data=%s", _ENTITY_ID, proto, util.serialize(data))
	send_package(_SEND_REQUEST(proto, data or {}))
	return true
end


skynet.init(function ()
	const = sharedata.query "const"
end)

local function generate_entity_id()
	return skynet.self() + tonumber(skynet.getenv("proc_id")) * 1000000000
end

skynet.start(function()
	_ENTITY_ID = generate_entity_id()
	logger.info("gateway_agent created, entity_id=%s", _ENTITY_ID)

	-- 注册一个 Lua 协议处理器，用于处理来自网关的消息。
	skynet.dispatch("lua", function(_, _, command, ...)
		-- skynet.trace() 这行代码是用于调试的，它会在控制台输出当前的调用栈信息。
		-- 这可以帮助开发者更好地理解代码的执行流程，特别是在需要调试复杂的逻辑时。
		-- 在生产环境中，通常会关闭这个调试功能，以提高性能。
		skynet.trace("gateway_agent_dispatch")
		local f = assert(CMD[command])
		skynet.ret(skynet.pack(f(...)))
	end)
end)
