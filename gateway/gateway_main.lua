local skynet = require "skynet"
require "skynet.manager"

local cluster = require "skynet.cluster"
local logger = require "common.logger"
local debug_console = require "common.debug_console_ex"
local util = require "common.util"


skynet.init(function()
	logger.info("gateway server initialized")
end)


skynet.start(function()
	-- 初始化业务日志记录器
	local nodename = skynet.getenv("nodename") or "gateway"
    local server_id = skynet.getenv("server_id")
	local proc_id = skynet.getenv("proc_id")
	assert(nodename and server_id and proc_id)

	local log_dir = "../log/" .. nodename .. "_" .. server_id .. "_" .. proc_id
	logger.init({base_dir = log_dir})
	logger.info("business logger initialized")

	-- 启动配置管理服务，用于管理配置文件
	skynet.uniqueservice("config_mgr")
	-- 启动消息处理服务，用于统一处理本进程与其他进程服务消息
	skynet.uniqueservice("service/handle_message")
	-- 启动协议加载服务
	skynet.uniqueservice("protoloader")
	
	
	-- 打开当前节点的集群功能，允许其他集群节点与本节点通信
    local cluster_name = nodename .. "_" .. server_id .. "_" .. proc_id
	cluster.open(cluster_name)

    -- 获取网关服务的端口和最大客户端数
	local port = tonumber(skynet.getenv("gateway_port"))
	local maxclient = tonumber(skynet.getenv("gateway_maxclient")) or 1024
    logger.info("port: %s, maxclient: %s", tostring(port), tostring(maxclient))
	local gateway_watchdog = skynet.newservice("service/gateway_watchdog")
	skynet.call(gateway_watchdog, "lua", "start", {
		address = "0.0.0.0",
		port = port,
		maxclient = maxclient,
		nodelay = true
	})

	debug_console.start()
	skynet.register(".gateway_main")
	logger.info("Gateway server started")

	
end)



