local skynet = require "skynet"
local logger = require "common.logger"
local snutil = require "common.snutil"
local sharedata = require "skynet.sharedata"
local util = require "common.util"

-- 服务器信息列表
local _SERVER_INFO_LIST = {}

local const = nil

local load_server_info_list = function()
    local ret, result = skynet.call(".sk_login", "lua", "select_all", "server_list")
    if ret and result then
        for _, server_info in ipairs(result) do
            _SERVER_INFO_LIST[server_info.id] = server_info
        end
        logger.info("load_server_info_list, ret: %s, result: %s", ret, util.serialize(_SERVER_INFO_LIST))
    end
end

local CMD = {}

function CMD.get_server_info_list()
    load_server_info_list()
    return _SERVER_INFO_LIST
end


skynet.init(function()
    const = sharedata.query "const"

end)


skynet.start(function()
    skynet.dispatch("lua", function(session, _, cmd, ...)
		snutil.lua_docmd(session, CMD, cmd, ...)
	end)

    --load_server_info_list()
	logger.info("server_list started")
end)