local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local graceful_stop = require "common.graceful_stop"

local _CUR_BEST_WORLD_PROC_ID = nil
-- acc_id -> {token = token, expire = os.time() + 300}
local _LOGIN_SESSION_INFO = {}
local _LOGIN_SESSION_INFO_EXPIRE_TIME = 300

local CMD = {}


-- 验证是否能够登陆
--@acc_id: 帐号唯一ID
--@token: 登录令牌
function CMD.check_agent_login(acc_id, token)
	logger.info("check_agent_login, acc_id=%s, token=%s", acc_id, token)
	if _LOGIN_SESSION_INFO and _LOGIN_SESSION_INFO[acc_id] and
		_LOGIN_SESSION_INFO[acc_id].token == token then
		return true
	else
		logger.info("check_agent_login failed, acc_id=%s, token=%s", acc_id, token)
	end
	return false
end

--@acc_id: 帐号唯一ID
function CMD.remove_login_session_info(acc_id)
	acc_id = tonumber(acc_id)
	logger.info("remove_login_session_info, acc_id=%s", acc_id)
	if _LOGIN_SESSION_INFO and _LOGIN_SESSION_INFO[acc_id] then
		_LOGIN_SESSION_INFO[acc_id] = nil
	end
	return true
end


-- 同步登录会话信息
--@acc_id: 帐号唯一ID
--@token: 登录令牌
function CMD.sync_login_agent_session_info(acc_id, token)
	acc_id = tonumber(acc_id)
	logger.info("sync_login_agent_session_info, acc_id=%s, token=%s", acc_id, token)
	_LOGIN_SESSION_INFO[acc_id] = {token = token, expire = os.time() + _LOGIN_SESSION_INFO_EXPIRE_TIME}
	logger.info("sync_login_agent_session_info, _LOGIN_SESSION_INFO=%s", util.serialize(_LOGIN_SESSION_INFO))
	return true
end


--@proc_id
function CMD.sync_cur_open_world_proc(proc_id)
	proc_id = tonumber(proc_id)
	if not proc_id then
		return false
	end
	_CUR_BEST_WORLD_PROC_ID = proc_id
	logger.info("sync_cur_open_world_proc, proc_id=%s", _CUR_BEST_WORLD_PROC_ID)
	return true
end


function CMD.get_cur_open_world_proc()
	if not _CUR_BEST_WORLD_PROC_ID then
		-- 缺省处理
		return 1
	end
	return _CUR_BEST_WORLD_PROC_ID
end

function CMD.graceful_stop()
	logger.info("gateway graceful_stop begin")
	pcall(skynet.call, ".gateway_watchdog", "lua", "graceful_stop")
	return graceful_stop.finish()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)

	skynet.register(".handle_message")

	skynet.fork(function()
		while true do
			for acc_id, info in pairs(_LOGIN_SESSION_INFO) do
				if info and info.expire and info.expire < os.time() then
					logger.info("check_agent_login_timeout, acc_id=%s, token=%s, expire=%s", acc_id, info.token, info.expire)
					_LOGIN_SESSION_INFO[acc_id] = nil
				end
			end
			skynet.sleep(100 * _LOGIN_SESSION_INFO_EXPIRE_TIME)
		end
	end)
	logger.info("gateway handle_message started")
end)
