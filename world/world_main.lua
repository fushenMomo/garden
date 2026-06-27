local skynet = require "skynet"
require "skynet.manager"

local cluster = require "skynet.cluster"
local logger = require "common.logger"
local debug_console = require "common.debug_console_ex"
local proc_state = require "common.proc_state"
local graceful_stop = require "common.graceful_stop"

skynet.init(function()
	logger.info("world server initialized")
end)

local function init_db_mysql()
	local db_name = string.format(skynet.getenv("DB_GAME_NAME"), tostring(skynet.getenv("server_id")))
	local db_host = skynet.getenv("DB_GAME_HOST")
	local db_port = tonumber(skynet.getenv("DB_GAME_PORT"))
	local db_user = skynet.getenv("DB_GAME_USER")
	local db_password = skynet.getenv("DB_GAME_PASSWORD")
	if db_name and db_host and db_port and db_user and db_password then
		local mysqlpool = skynet.newservice("mysqlpool")
		local server_name = ".db_game" -- 个人相关数据
		skynet.call(mysqlpool, "lua", "open", 
					{name = server_name, host = db_host, port = db_port, database = db_name, user = db_user, password = db_password, maxconn = 10})
		logger.info("mysqlpool started, db=%s host=%s port=%s", db_name, db_host, tostring(db_port))
	else
		logger.err("mysqlpool start skipped: missing DB_GAME_* config")
	end

	db_name = string.format(skynet.getenv("DB_GLOBAL_NAME"), tostring(skynet.getenv("server_id")))
	db_host = skynet.getenv("DB_GLOBAL_HOST")
	db_port = tonumber(skynet.getenv("DB_GLOBAL_PORT"))
	db_user = skynet.getenv("DB_GLOBAL_USER")
	db_password = skynet.getenv("DB_GLOBAL_PASSWORD")
	if db_name and db_host and db_port and db_user and db_password then
		local mysqlpool = skynet.newservice("mysqlpool")
		local server_name = ".db_global" -- 全局相关数据
		skynet.call(mysqlpool, "lua", "open", 
					{name = server_name, host = db_host, port = db_port, database = db_name, user = db_user, password = db_password, maxconn = 10})
		logger.info("mysqlpool started, db=%s host=%s port=%s", db_name, db_host, tostring(db_port))
	else
		logger.err("mysqlpool start skipped: missing DB_GLOBAL_* config")
	end
end

local function init_db_redis()
	local redis_host = skynet.getenv("REDIS_HOST")
	local redis_port = tonumber(skynet.getenv("REDIS_PORT"))
	local redis_password = skynet.getenv("REDIS_PASSWORD")
	local redis_db_index = tonumber(skynet.getenv("REDIS_DB_INDEX"))
	if redis_host and redis_port and redis_password then
		local redispool = skynet.newservice("redispool")
		local server_name = ".redis"
		skynet.call(redispool, "lua", "open", 
					{name = server_name, host = redis_host, port = redis_port, password = redis_password, db = redis_db_index})
		logger.info("redispool started, db=%s host=%s port=%s", server_name, redis_host, tostring(redis_port))
	else
		logger.err("redispool start skipped: missing REDIS_* config")
	end
end


local function init_world_func()
	local world_func_flag = skynet.getenv("WORLD_FUNC_FLAG")
	if world_func_flag then
		logger.info("world_func_flag=%s", world_func_flag)
		if world_func_flag == "guild" then
			-- 启动公会管理服务
			logger.info("world_func_flag is guild")
			skynet.uniqueservice("service/standalone/guild_manager")
		else
			logger.err("world_func_flag is not supported: %s", world_func_flag)
		end
	end
end

skynet.start(function()
	
	local nodename = skynet.getenv("nodename")
    local server_id = skynet.getenv("server_id")
	local proc_id = skynet.getenv("proc_id")
	assert(nodename and server_id and proc_id)
	-- 打开当前节点的集群功能，允许其他集群节点与本节点通信
    local cluster_name = nodename .. "_" .. server_id .. "_" .. proc_id
	cluster.open(cluster_name)

	local log_dir = "../log/" .. nodename .. "_" .. server_id .. "_" .. proc_id
	logger.init({base_dir = log_dir})
	logger.info("business logger initialized")

	-- 启动配置管理服务，用于管理配置文件
	skynet.uniqueservice("config_mgr")
	proc_state.report(0)

	init_db_mysql()
	init_db_redis()

	skynet.uniqueservice("service/handle_message")
	if not skynet.getenv("WORLD_FUNC_FLAG") then
		skynet.uniqueservice("service/standalone/fighting_mgr")
	end
	graceful_stop.start_listener()

	-- 可持久化定时器（Redis ZSET + 启动恢复）
	skynet.uniqueservice("service/timer_service")

	init_world_func()

	debug_console.start()
	skynet.register(".world_main")
	proc_state.running()
	logger.info("World server started")
end)
