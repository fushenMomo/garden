thread = 8
harbor = 0
start = "login_main"
bootstrap = "snlua bootstrap"	-- The service for bootstrap
luaservice = "../login/?.lua;../common/?.lua;./service/?.lua;"
lualoader = "./lualib/loader.lua"

-- 给 require 用
lua_path = "./lualib/?.lua;./lualib/?/init.lua;../?.lua"
lua_cpath = "./luaclib/?.so"


-- C 服务（比如 logger.so）
cpath = "./cservice/?.so"

-- 集群
nodename = "login"
cluster = "../etc/clustername.login"

-- 日志
daemon = "../log/login/login.pid"
logger = "../log/login/login_core.log"
logger_level = "INFO"

debug_console = 9000
login_port = 8888
login_maxclient = 1024
login_package_max = 8192

-- 数据库代理
DB_LOGIN_NAME = "sk_login"
DB_LOGIN_HOST = "192.168.178.129"
DB_LOGIN_PORT = 3306
DB_LOGIN_USER = "yaofan"
DB_LOGIN_PASSWORD = "123456"

REDIS_HOST = "192.168.178.129"
REDIS_PORT = 8001
REDIS_PASSWORD = "r12345"
REDIS_DB_INDEX = 1


