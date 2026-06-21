local skynet = require "skynet"
local json = require "common.json_min"
local logger = require "common.logger"

local M = {}

M.handlers = {}

local function parse_body(ctx)
	if not ctx.body or ctx.body == "" then
		return {}
	end
	local ok, data = pcall(json.decode, ctx.body)
	if not ok then
		return nil, "invalid json body"
	end
	return data
end

function M.handlers.kick(ctx)
	if ctx.method ~= "POST" then
		return {http_status = 405, msg = "method not allowed"}
	end
	local data, err = parse_body(ctx)
	if not data then
		return {http_status = 400, msg = err}
	end
	local acc_id = tonumber(data.acc_id)
	local server_id = tonumber(data.server_id) or 1
	if not acc_id then
		return {http_status = 400, msg = "acc_id required"}
	end
	logger.info("player kick, acc_id=%s server_id=%s", acc_id, server_id)
	local ret = skynet.call(".handle_message", "lua", "call_worldmgr", server_id, "web_kick_player", acc_id)
	return {msg = "ok", data = ret}
end

function M.handlers.ban(ctx)
	if ctx.method ~= "POST" then
		return {http_status = 405, msg = "method not allowed"}
	end
	local data, err = parse_body(ctx)
	if not data then
		return {http_status = 400, msg = err}
	end
	local acc_id = tonumber(data.acc_id)
	if not acc_id then
		return {http_status = 400, msg = "acc_id required"}
	end
	logger.info("player ban, acc_id=%s", acc_id)
	local ret = skynet.call(".handle_message", "lua", "call_servermgr", "web_ban_player", acc_id, data.reason)
	return {msg = "ok", data = ret}
end

function M.on_notify(action, data)
	logger.info("player on_notify action=%s", tostring(action))
	return true
end

return M
