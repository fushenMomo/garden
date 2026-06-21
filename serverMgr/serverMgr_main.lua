local skynet = require "skynet"
require "skynet.manager"

local cluster = require "skynet.cluster"
local logger = require "common.logger"
local debug_console = require "common.debug_console_ex"


skynet.init(function()
	logger.info("serverMgr server initialized")
end)


skynet.start(function()
	
	logger.init()
	logger.info("business logger initialized")
	skynet.uniqueservice("config_mgr")
	skynet.uniqueservice("service/handle_message")

	local nodename = skynet.getenv("nodename")
	local server_id = skynet.getenv("server_id")
	local proc_id = skynet.getenv("proc_id")
	assert(nodename and server_id and proc_id)

	local cluster_name = nodename .. "_" .. server_id .. "_" .. proc_id
	cluster.open(cluster_name)


	debug_console.start()
	skynet.register(".serverMgr_main")
	logger.info("ServerMgr server started")
end)
