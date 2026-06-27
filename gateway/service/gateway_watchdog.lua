local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local util = require "common.util"
local cluster_login = require "common.cluster_login"

local CMD = {}
local SOCKET = {}
local _GATE
local _AGENT_BY_FD = {} -- 客户端连接 fd 对应的 agent 服务地址
local _AGENT_BY_ENTITY = {} -- entity_id 对应的 agent 服务地址
local _ENTITY_BY_FD = {} -- 客户端连接 fd 对应的 entity_id
local _FD_BY_ENTITY = {} -- entity_id 对应的客户端连接 fd
local _CLIENT_COUNT = nil

function SOCKET.open(client_fd, addr)
	logger.info(string.format("gateway client connected fd=%d addr=%s", client_fd, addr))
    local agent = skynet.newservice("service/gateway_agent")
	local entity_id = skynet.call(agent, "lua", "start", {
		gate = _GATE,-- 网关服务地址
		client = client_fd,-- 客户端连接 fd
		watchdog = skynet.self()-- 网关服务监视器地址
	})
	_AGENT_BY_FD[client_fd] = agent
	_AGENT_BY_ENTITY[entity_id] = agent
	_ENTITY_BY_FD[client_fd] = entity_id
	_FD_BY_ENTITY[entity_id] = client_fd
end

-- 当客户端连接关闭时，停止 agent 服务，并将其从 _AGENT_BY_FD 中删除
local function close_agent(fd)
	local agent = _AGENT_BY_FD[fd]
	local entity_id = _ENTITY_BY_FD[fd]
	_AGENT_BY_FD[fd] = nil
	_ENTITY_BY_FD[fd] = nil
	_FD_BY_ENTITY[entity_id] = nil
	if entity_id then
		_AGENT_BY_ENTITY[entity_id] = nil
	end
	if agent then
		skynet.call(_GATE, "lua", "kick", fd)
		skynet.send(agent, "lua", "disconnect")
	end
end

-- 当客户端连接关闭时，停止 agent 服务，并将其从 _AGENT_BY_FD 中删除
function SOCKET.close(fd)
	logger.info(string.format("gateway socket close fd=%d", fd))
	close_agent(fd)
end

-- 当客户端连接发生错误时，停止 agent 服务，并将其从 _AGENT_BY_FD 中删除
function SOCKET.error(fd, msg)
	logger.info(string.format("gateway socket error fd=%d %s", fd, tostring(msg)))
	close_agent(fd)
end

-- 当客户端连接发生警告时，记录警告信息
function SOCKET.warning(fd, size)
	logger.info(string.format("gateway socket warning fd=%d backlog=%sK", fd, tostring(size)))
end

-- 当客户端连接有数据时，记录数据信息
function SOCKET.data(fd, msg)
	logger.info("gateway socket data fd=%d msg=%s", fd, tostring(msg))
end

-- 启动登录服务监视器，初始化配置并打开网关
function CMD.start(conf)
	conf = conf or {}
	conf.watchdog = conf.watchdog or skynet.self()
	return skynet.call(_GATE, "lua", "open", conf)
end


function CMD.player_disconnect(msg)
	local entity_id = msg.entity_id
	local fd = _FD_BY_ENTITY[entity_id]
	if fd then
		close_agent(fd)
	end
end


function CMD.push_to_client(msg)
	local entity_id = msg.entity_id
	local proto = msg.proto
	local data = msg.data or {}
	local agent_address = _AGENT_BY_ENTITY[entity_id]
	if not agent_address then
		logger.error("push_to_client failed, agent not found, entity_id=%s, proto=%s", entity_id, proto)
		return false
	end
	skynet.send(agent_address, "lua", "push_to_client", proto, data)
	logger.info("push_to_client success, entity_id=%s, proto=%s, agent=%s", entity_id, proto, agent_address)
	return true
end


-- 当客户端连接关闭时，停止 agent 服务，并将其从 agent_by_fd 中删除
function CMD.close(fd)
	close_agent(fd)
end

function CMD.graceful_stop()
	local fds = {}
	for fd in pairs(_AGENT_BY_FD) do
		fds[#fds + 1] = fd
	end
	for _, fd in ipairs(fds) do
		pcall(close_agent, fd)
	end
	return true
end

local function get_client_count()
	local client_count = 0
	for _, agent in pairs(_AGENT_BY_FD) do
		if agent then
			client_count = client_count + 1
		end
	end
	return client_count
end

--@server_id
--@proc_id
--@port
local function sync_gateway_port2login(server_id, proc_id, port, client_count)
	if server_id == nil or proc_id == nil or port == nil or client_count == nil then
		return false
	end
	logger.info("sync_gateway_port2login, server_id:%s, proc_id:%s, port:%s", server_id, proc_id, port)
	server_id = tonumber(server_id)
	proc_id = tonumber(proc_id)
	port = tonumber(port)
	client_count = tonumber(client_count)
	cluster_login.broadcast(
		".login_watchdog",
		"sync_gateway_port",
		server_id,
		proc_id,
		port,
		client_count
	)
	return true
end


local function update_info2login()
	skynet.fork(function()
		while true do
			local client_count = get_client_count()
			if _CLIENT_COUNT ~= client_count then
				_CLIENT_COUNT = client_count
				sync_gateway_port2login(
					skynet.getenv("server_id"), 
					skynet.getenv("proc_id"), 
					skynet.getenv("gateway_port"),
					client_count
				)
			end
			skynet.sleep(100 * 60) -- 每分钟同步一次
		end
	end)
end


skynet.start(function()
	skynet.dispatch("lua", function(session, _, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			assert(f, subcmd)
			f(...)
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	-- 启动网关服务，用于管理客户端连接
	_GATE = skynet.newservice("gate")

	-- 记录日志，登录服务监视器准备就绪
	logger.info("gateway_watchdog ready: gate=%s", tostring(_GATE))
	skynet.register(".gateway_watchdog")

	--------------------------------------------------------------------------------------
    -- gateway进程的gateway_watchdog服务启动完成之后，
	-- 发送一条消息给login进程的login_watchdog服务,同步其端口号
	update_info2login()
	
end)
