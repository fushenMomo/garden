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

function M.handlers.info(ctx)
	if ctx.method ~= "GET" and ctx.method ~= "POST" then
		return {http_status = 405, msg = "method not allowed"}
	end
	local guild_id
	if ctx.method == "GET" then
		guild_id = tonumber(ctx.query.guild_id)
	else
		local data, err = parse_body(ctx)
		if not data then
			return {http_status = 400, msg = err}
		end
		guild_id = tonumber(data.guild_id)
	end
	if not guild_id then
		return {http_status = 400, msg = "guild_id required"}
	end
	local server_id = tonumber(ctx.query.server_id or ctx.header["x-server-id"]) or 1
	local proc_id = tonumber(ctx.query.proc_id) or 1
	logger.info("guild info, guild_id=%s server_id=%s proc_id=%s", guild_id, server_id, proc_id)
	local ret = skynet.call(".handle_message", "lua", "call_world", server_id, proc_id, "web_guild_info", guild_id)
	return {msg = "ok", data = ret}
end

function M.on_notify(action, data)
	logger.info("guild on_notify action=%s", tostring(action))
	return true
end

return M
