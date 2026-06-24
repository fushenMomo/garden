local skynet = require "skynet"
require "skynet.manager"

local cluster = require "skynet.cluster"
local logger = require "common.logger"
local debug_console = require "common.debug_console_ex"
local proc_state = require "common.proc_state"
local graceful_stop = require "common.graceful_stop"

local function init_db_mysql()
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
			password = db_password,
		})
		logger.info("mysqlpool started, db=%s host=%s port=%s", db_name, db_host, tostring(db_port))
	else
		logger.error("mysqlpool start skipped: missing DB_LOGIN_* config")
	end
end

local function init_db_redis()
	local redis_host = skynet.getenv("REDIS_HOST")
	local redis_port = tonumber(skynet.getenv("REDIS_PORT"))
	local redis_password = skynet.getenv("REDIS_PASSWORD")
	local redis_db_index = tonumber(skynet.getenv("REDIS_DB_INDEX"))
	if redis_host and redis_port and redis_password then
		local redispool = skynet.newservice("redispool")
		skynet.call(redispool, "lua", "open", {
			name = ".redis",
			host = redis_host,
			port = redis_port,
			password = redis_password,
			db = redis_db_index,
		})
		logger.info("redispool started, host=%s port=%s", redis_host, tostring(redis_port))
	else
		logger.error("redispool start skipped: missing REDIS_* config")
	end
end

skynet.start(function()
	local nodename = skynet.getenv("nodename")
	local server_id = skynet.getenv("server_id")
	local proc_id = skynet.getenv("proc_id")
	assert(nodename and server_id and proc_id)

	local cluster_name = nodename .. "_" .. server_id .. "_" .. proc_id
	cluster.open(cluster_name)

	local log_dir = "../log/" .. nodename .. "_" .. server_id .. "_" .. proc_id
	logger.init({ base_dir = log_dir })

	skynet.uniqueservice("config_mgr")
	proc_state.report(0)
	skynet.uniqueservice("service/handle_message")
	graceful_stop.start_listener()

	skynet.uniqueservice("service/server_map")
	init_db_mysql()
	init_db_redis()

	skynet.uniqueservice("service/bi_push")
	skynet.uniqueservice("service/bi_consumer")

	proc_state.running()
	debug_console.start()
	skynet.register(".bi_main")
	logger.info("BI server started, cluster=%s", cluster_name)
end)
