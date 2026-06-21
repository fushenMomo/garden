local skynet = require "skynet"

local crypt = require "skynet.crypt"
local logger = require "common.logger"

local snutil = require "common.snutil"
local sharedata = require "skynet.sharedata"
local util = require "common.util"


local CMD = {}
local const = nil


-- 重要的成员变量
-- token -> { acc_id = number, expire = skynet.time seconds }
local _SESSIONS = {}
local _SESSION_TOKEN_BY_ACC_ID = {}
local SESSION_TTL = 300



--@password
--@salt_hex
local function hash_password(password, salt_hex)
	local blob = password .. ":" .. salt_hex
	return crypt.hexencode(crypt.sha1(blob))
end

--@password
local function encode_password_for_store(password)
	-- 格式：salt$hash，后续校验时先拆出 salt 再算 hash 比较
	local salt_hex = crypt.hexencode(crypt.randomkey())
	local pass_hash = hash_password(password, salt_hex)
	return string.format("%s$%s", salt_hex, pass_hash)
end

--@stored_password
--@input_password
local function verify_password(stored_password, input_password)
	if type(stored_password) ~= "string" then
		return false
	end

	-- 新格式：salt$hash
	local salt_hex, pass_hash = string.match(stored_password, "^([0-9a-fA-F]+)%$([0-9a-fA-F]+)$")
	if salt_hex and pass_hash then
		return hash_password(input_password, salt_hex) == string.lower(pass_hash)
	end
	return false
end

local function now()
	return skynet.time()
end

--检查account是否存在
--@account
local function get_account_id(account)
	local ret, result = skynet.call(".sk_login", "lua", "select_one_by_key", "login_info", "account", account)
	if ret and result then
		return result.act_id
	end
	return 0
end

local function get_account_row(account)
	local ret, result = skynet.call(".sk_login", "lua", "select_one_by_key", "login_info", "account", account)
	if ret and result then
		return result
	end
	return nil
end

--@account
--@password
--@platform
local function insert_account(account, password, platform)
	local encoded_password = encode_password_for_store(password)
	local ret, act_id = skynet.call(".sk_login", "lua", "insert", "login_info", {
		account = account,
		password = encoded_password,
		register_time = os.date("%Y-%m-%d %H:%M:%S", os.time()),
		platform_id = platform,
	})
	logger.info("insert_account, ret: %s, act_id: %s", ret, act_id)
	return ret and act_id or 0
end


--@username
--@pasword
--@platform
function CMD.register(username, password, platform)
	assert(username and username ~= "", "username required")
	assert(password and password ~= "", "password required")
	assert(platform and platform ~= "", "platform required")

	if #username > 64 or #password > 128 then
		return const.error_code.name_or_pass_too_long
	end

	if platform < const.login_type.default or platform > const.login_type.max then
		return const.error_code.platform_error
	end

	-- 检查帐号是否存在
	local acc_id = get_account_id(username)
	if acc_id ~= 0 then
		return const.error_code.user_exists
	end

	-- 插入帐号
	acc_id = insert_account(username, password, platform)	
	if acc_id == 0 then
		return const.error_code.insert_account_failed, acc_id
	end

	return const.error_code.success, acc_id
end



--@username
--@pasword
--@platform
function CMD.login(username, password, platform)
	assert(username and username ~= "", "username required")
	assert(password and password ~= "", "password required")
	assert(platform and platform ~= "", "platform required")

	if platform < const.login_type.default or platform > const.login_type.max then
		return const.error_code.platform_error
	end

	local row = get_account_row(username)
	if not row then
		return const.error_code.unknown_user
	end

	local ok = verify_password(row.password, password)
	if not ok then
		return const.error_code.bad_password
	end

	-- 顶号处理 将旧的会话token删除
	local old_token = _SESSION_TOKEN_BY_ACC_ID[row.act_id]
	if old_token and _SESSIONS[old_token] then
		_SESSIONS[old_token] = nil
	end

	-- 生成一个会话 token：先生成一个随机字节串，然后编码为16进制字符串，作为当前登录会话的唯一凭证
	local token = crypt.hexencode(crypt.randomkey())

	_SESSIONS[token] = {
		acc_id = row.act_id,
		expire = now() + SESSION_TTL,
	}
	_SESSION_TOKEN_BY_ACC_ID[row.act_id] = token

	return const.error_code.success, row.act_id, token
end


--@acc_id: 帐号唯一ID
local function remove_session(acc_id)
	if _SESSION_TOKEN_BY_ACC_ID[acc_id] then
		local token = _SESSION_TOKEN_BY_ACC_ID[acc_id]
		if token and _SESSIONS[token] then
			_SESSION_TOKEN_BY_ACC_ID[acc_id] = nil
			_SESSIONS[token] = nil
		end
	end
end

--@acc_id: 帐号唯一ID
function CMD.check_timeout(acc_id)
	logger.info("account_service check_timeout, acc_id: %s", acc_id)
	if _SESSION_TOKEN_BY_ACC_ID[acc_id] then
		local token = _SESSION_TOKEN_BY_ACC_ID[acc_id]
		if token and _SESSIONS[token] then
			local s = _SESSIONS[token]
			if now() > s.expire then
				--_SESSION_TOKEN_BY_ACC_ID[acc_id] = nil
				--_SESSIONS[token] = nil
				remove_session(acc_id)
				return true
			end
		end
	end
	return false
end

--@acc_id: 帐号唯一ID
function CMD.heartbeat(acc_id)
	logger.info("account_service heartbeat, acc_id: %s", acc_id)
	if _SESSION_TOKEN_BY_ACC_ID[acc_id] then
		local token = _SESSION_TOKEN_BY_ACC_ID[acc_id]
		if token and _SESSIONS[token] then
			local s = _SESSIONS[token]
			s.expire = now() + SESSION_TTL
		end
	end
	return const.error_code.success
end


--- Optional: validate token (for game nodes later)
--[[
function CMD.verify_token(token)
	if not token or token == "" then
		return const.error_code.bad_token
	end

	local s = _SESSIONS[token]
	if not s then
		return const.error_code.bad_token
	end

	if now() > s.expire then
		if _SESSION_TOKEN_BY_ACC_ID[s.acc_id] == token then
			_SESSION_TOKEN_BY_ACC_ID[s.acc_id] = nil
		end
		_SESSIONS[token] = nil
		return const.error_code.expired
	end

	return const.error_code.success, s.acc_id
end
--]]


skynet.init(function()
	const = sharedata.query "const"

end)

skynet.start(function()
	skynet.dispatch("lua", function(session, _, cmd, ...)
		snutil.lua_docmd(session, CMD, cmd, ...)
	end)

	logger.info("account_service started")
end)

