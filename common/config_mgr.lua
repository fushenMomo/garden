local skynet = require "skynet"
require "skynet.manager" -- skynet.register
local sharedata = require "skynet.sharedata"
local snutil = require "common.snutil"
local logger = require "common.logger"

local CMD = {}
local _self = {is_loading = nil}

local function load_res(res_path)
    local f = assert(io.open(res_path, "r"))
    local conf = load(f:read("*a"))()
    f:close()
    return conf
end

local reload_list = {
    ["const"] = "../common/const.lua",
    ["sensitive_words"] = "../common/sensitive_words.lua",
    ["cfg_item"] = "../config/cfg_item.lua",
}

function CMD.reloadall()
    _self.is_loading = true
    for res_name, res_path in pairs(reload_list) do
        --logger.info("Loading " .. res_path)
        local conf = load_res(res_path)
        --logger.info("Loaded " .. res_path)
        sharedata.update(res_name, conf)
        logger.info("Updated " .. res_path)
    end
    _self.is_loading = false
end

function _self.reloadall()
    logger.info("Reloading all configs")
    CMD.reloadall()
end

function CMD.reload(res_path)
    if not reload_list[res_path] then
        error(string.format("Unknonw res_path %s", tostring(res_path)))
    end
    _self.is_loading = true
    local conf = load_res(reload_list[res_path])
    sharedata.update(res_path, conf)
    _self.is_loading = false
end

skynet.init(function()
    _self.reloadall()
end)

skynet.start(function()
	skynet.dispatch("lua", function(session,source,cmd, ...)
		local f = CMD[cmd]
        if not f then
            error(string.format("Unknonw CMD %s", tostring(cmd)))
        end
        
        local ok, err = xpcall(snutil.lua_docmd, snutil.handle_err, session, CMD, cmd, ...)
        if not ok then
            logger.info(string.format("%s error, cmd=%s, session=%s, source=%s, args=%s", 
                    ".config_mgr", cmd, session, source, tostring({...})))
            error(err)
        end
	end)
    skynet.register ".config_mgr"
end)

