local skynet = require "skynet"
require "skynet.manager"
local logger = require "common.logger"
local util = require "common.util"

-- 这里相当于C++类中的private成员变量
local CMD = {} -- 命令列表	
local SOCKET = {} -- 套接字事件处理函数列表
local _GATE -- 网关服务地址
local _AGENT_BY_FD = {} -- 客户端连接 fd 对应的 agent 服务地址
local _SERVER_SYNC_LIST = {} -- 服务器同步信息列表


local _CHECK_INTERVAL_TICK = 5 * 60 * 100 -- 5分钟检查一次，1秒=100tick

-- 当有新的客户端连接时，创建一个新的 agent 服务，并将其地址存储在 _AGENT_BY_FD 中
function SOCKET.open(client_fd, addr)
	logger.info(string.format("login client connected fd=%d addr=%s", client_fd, addr))
	local agent = skynet.newservice("service/login_agent")
	_AGENT_BY_FD[client_fd] = agent
	skynet.call(agent, "lua", "start", {
		gate = _GATE,-- 网关服务地址
		client = client_fd,-- 客户端连接 fd
		watchdog = skynet.self()-- 登录服务监视器地址
	})
end

-- 当客户端连接关闭时，停止 agent 服务，并将其从 _AGENT_BY_FD 中删除
local function close_agent(fd)
	local agent = _AGENT_BY_FD[fd]
	_AGENT_BY_FD[fd] = nil
	if agent then
		skynet.call(_GATE, "lua", "kick", fd)
		skynet.send(agent, "lua", "disconnect")
	end
end

-- 当客户端连接关闭时，停止 agent 服务，并将其从 _AGENT_BY_FD 中删除
function SOCKET.close(fd)
	logger.info(string.format("login socket close fd=%d", fd))
	close_agent(fd)
end

-- 当客户端连接发生错误时，停止 agent 服务，并将其从 _AGENT_BY_FD 中删除
function SOCKET.error(fd, msg)
	logger.info(string.format("login socket error fd=%d %s", fd, tostring(msg)))
	close_agent(fd)
end

-- 当客户端连接发生警告时，记录警告信息
function SOCKET.warning(fd, size)
	logger.info(string.format("login socket warning fd=%d backlog=%sK", fd, tostring(size)))
end

-- 当客户端连接有数据时，记录数据信息
function SOCKET.data(fd, msg)
	logger.info("login socket data fd=%d msg=%s", fd, tostring(msg))
end


-- 启动登录服务监视器，初始化配置并打开网关
function CMD.start(conf)
	conf = conf or {}
	conf.watchdog = conf.watchdog or skynet.self()
	return skynet.call(_GATE, "lua", "open", conf)
end

-- 当客户端连接关闭时，停止 agent 服务，并将其从 agent_by_fd 中删除
function CMD.close(fd)
	close_agent(fd)
end

-- 同步网关服务端口号
--@server_id
--@proc_id
--@port
--@client_count
function CMD.sync_gateway_port(server_id, proc_id, port, client_count)
	if not server_id or not proc_id or not port then
		return false
	end
	server_id = tonumber(server_id)
	proc_id = tonumber(proc_id)
	port = tonumber(port)
	client_count = tonumber(client_count)
	logger.info("sync_gateway_port, server_id=%s, proc_id=%s, port=%s, client_count=%s", server_id, proc_id, port, client_count)
	if not _SERVER_SYNC_LIST[server_id] then
		_SERVER_SYNC_LIST[server_id] = {}
	end
	_SERVER_SYNC_LIST[server_id][proc_id] = {host = "127.0.0.1", port = port, client_count = client_count}
	logger.info("sync_gateway_port, server_sync_list: %s", util.serialize(_SERVER_SYNC_LIST))
	return true
end


function CMD.get_server_info(server_id)
	return _SERVER_SYNC_LIST and _SERVER_SYNC_LIST[server_id] or nil
end

local function check_login_agent_timeout()
	local timeout_fds = {}
	for fd, agent in pairs(_AGENT_BY_FD) do
		local ok, is_timeout  = pcall(
			skynet.call,
			agent,
			"lua",
			"check_timeout"
		)
		if ok and is_timeout then
			table.insert(timeout_fds, fd)
		end
	end
	if #timeout_fds <= 0 then
		return
	end
	logger.info("check_login_agent_timeout, timeout_fds: %s", util.serialize(timeout_fds))
	for _, fd in ipairs(timeout_fds) do
	 	close_agent(fd)
	end
end

local function start_login_agent_timeout_timer()
	local function schedule()
		skynet.timeout(_CHECK_INTERVAL_TICK, function()
			check_login_agent_timeout()
			schedule()
		end)
	end
	schedule()
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
	start_login_agent_timeout_timer()
	-- 记录日志，登录服务监视器准备就绪
	logger.info("login_watchdog ready: gate=%s", tostring(_GATE))
	skynet.register(".login_watchdog")
end)
