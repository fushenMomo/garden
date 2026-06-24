local skynet = require "skynet"
require "skynet.manager"

local cluster = require "skynet.cluster"
local logger = require "common.logger"
local debug_console = require "common.debug_console_ex"
local proc_state = require "common.proc_state"
local graceful_stop = require "common.graceful_stop"


skynet.init(function()
	logger.info("Login server initialized")
end)


local function init_db_mysql()
	logger.info("init_db_mysql")
	local db_name = skynet.getenv("DB_LOGIN_NAME")
	local db_host = skynet.getenv("DB_LOGIN_HOST")
	local db_port = tonumber(skynet.getenv("DB_LOGIN_PORT"))
	local db_user = skynet.getenv("DB_LOGIN_USER")
	local db_password = skynet.getenv("DB_LOGIN_PASSWORD")
	if db_name and db_host and db_port and db_user and db_password then
		local mysqlpool = skynet.newservice("mysqlpool")
		skynet.call(mysqlpool, "lua", "open", {
			name = "." .. db_name,
			host = db_host,
			port = db_port,
			database = db_name,
			user = db_user,
			password = db_password
		})
		logger.info("mysqlpool started, db=%s host=%s port=%s", db_name, db_host, tostring(db_port))
	else
		logger.err("mysqlpool start skipped: missing DB_LOGIN_* config")
	end
end

local function init_db_redis()
	local redis_host = skynet.getenv("REDIS_HOST")
	local redis_port = tonumber(skynet.getenv("REDIS_PORT"))
	local redis_password = skynet.getenv("REDIS_PASSWORD")
	local redis_db_index = tonumber(skynet.getenv("REDIS_DB_INDEX"))
	if redis_host and redis_port and redis_password then
		local redispool = skynet.newservice("redispool")
		skynet.call(redispool, "lua", "open",
			{name = ".redis", host = redis_host, port = redis_port, password = redis_password, db = redis_db_index})
		logger.info("redispool started, host=%s port=%s", redis_host, tostring(redis_port))
	else
		logger.err("redispool start skipped: missing REDIS_* config")
	end
end

skynet.start(function()
	-- 初始化业务日志记录器
	logger.init()
	logger.info("business logger initialized")
	-- 启动配置管理服务，用于管理配置文件
	skynet.uniqueservice("config_mgr")
	-- 启动协议加载服务
	skynet.uniqueservice("protoloader")
	-- 启动消息处理服务，用于统一处理本进程与其他进程服务消息
	skynet.uniqueservice("service/handle_message")
	graceful_stop.start_listener()
	
	local nodename = skynet.getenv("nodename")
	assert(nodename)
	-- 打开当前节点的集群功能，允许其他集群节点与本节点通信
	cluster.open(nodename)

	-- 启动账号服务，用于管理登录进程的账号信息
	local account_service = skynet.uniqueservice("service/account_service")
    skynet.name(".account_service", account_service)
	-- 启动服务器列表服务
	local server_list_service = skynet.uniqueservice("service/server_list")
	skynet.name(".server_list_service", server_list_service)

	-- 获取登录服务的端口和最大客户端数
	local port = tonumber(skynet.getenv("login_port")) or 8888
	local maxclient = tonumber(skynet.getenv("login_maxclient")) or 1024

    logger.info("port: %s, maxclient: %s", tostring(port), tostring(maxclient))
	local login_watchdog = skynet.newservice("service/login_watchdog")
	skynet.call(login_watchdog, "lua", "start", {
		address = "0.0.0.0",
		port = port,
		maxclient = maxclient,
		nodelay = true
	})

	-- 启动数据库代理服务 
	init_db_mysql()
	init_db_redis()

	proc_state.report(0)

	debug_console.start()
	-- 将当前服务注册为 ".login" 名字，方便外部通过名字查找和通信
	skynet.register(".login_main")
	proc_state.running()
	logger.info("Login server started")
	logger.info(string.format("login tcp listening on %s (maxclient=%s)", tostring(port), tostring(maxclient)))
end)

