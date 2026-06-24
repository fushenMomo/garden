local skynet = require "skynet"
require "skynet.manager"

local cluster = require "skynet.cluster"
local logger = require "common.logger"
local debug_console = require "common.debug_console_ex"
local proc_state = require "common.proc_state"
local graceful_stop = require "common.graceful_stop"


skynet.init(function()
	logger.info("serverMgr server initialized")
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


skynet.start(function()
	
	logger.init()
	logger.info("business logger initialized")
	skynet.uniqueservice("config_mgr")
	skynet.uniqueservice("service/handle_message")
	graceful_stop.start_listener()

	local nodename = skynet.getenv("nodename")
	assert(nodename)
	cluster.open(nodename)

	init_db_mysql()
	local proc_state_svc = skynet.uniqueservice("service/proc_state_service")
	skynet.name(".proc_state_service", proc_state_svc)
	proc_state.report(0)

	debug_console.start()
	skynet.register(".serverMgr_main")
	proc_state.running()
	logger.info("ServerMgr server started")
end)
