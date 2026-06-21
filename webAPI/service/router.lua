local skynet = require "skynet"
local json = require "common.json_min"
local logger = require "common.logger"
local modules = require "webAPI.service.module.init"

local M = {}

local function resp(code, data)
	data = data or {}
	data.code = data.code or code
	return code, json.encode(data)
end

local function check_auth(header)
	local api_key = skynet.getenv("web_api_key")
	if not api_key or api_key == "" then
		return true
	end
	local auth = header["authorization"] or header["Authorization"]
	if auth == api_key then
		return true
	end
	local key = header["x-api-key"] or header["X-Api-Key"]
	return key == api_key
end

function M.dispatch(method, path, query, body, header, addr)
	method = string.upper(method or "GET")
	header = header or {}

	if not check_auth(header) then
		return resp(401, {msg = "unauthorized"})
	end

	local parts = {}
	for seg in string.gmatch(path or "", "[^/]+") do
		parts[#parts + 1] = seg
	end

	if parts[1] ~= "api" or not parts[2] then
		return resp(404, {msg = "not found"})
	end

	local mod_name = parts[2]
	local action = parts[3] or "index"
	local mod = modules.get(mod_name)
	if not mod then
		return resp(404, {msg = "module not found"})
	end

	local handler = mod.handlers and mod.handlers[action]
	if not handler then
		return resp(404, {msg = "action not found"})
	end

	local ctx = {
		method = method,
		path = path,
		query = query,
		body = body,
		header = header,
		addr = addr,
		module = mod_name,
		action = action,
	}

	local ok, ret = pcall(handler, ctx)
	if not ok then
		logger.error("module handler error, module=%s action=%s err=%s", mod_name, action, tostring(ret))
		return resp(500, {msg = "handler error"})
	end

	if type(ret) == "table" then
		local status = ret.http_status or 200
		ret.http_status = nil
		return status, json.encode(ret)
	end

	return resp(200, {data = ret})
end

return M
