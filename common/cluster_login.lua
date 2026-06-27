local skynet = require "skynet"
local cluster = require "skynet.cluster"

local M = {}

local function get_login_count()
	return tonumber(skynet.getenv("login_count")) or 1
end

function M.cluster_name(proc_id)
	return string.format("login_%s", proc_id)
end

function M.self_cluster_name()
	if skynet.getenv("nodename") ~= "login" then
		return nil
	end
	local proc_id = tonumber(skynet.getenv("proc_id")) or 1
	return M.cluster_name(proc_id)
end

function M.each(fn)
	local count = get_login_count()
	for i = 1, count do
		fn(M.cluster_name(i), i)
	end
end

function M.broadcast(service, cmd, ...)
	local args = { ... }
	M.each(function(name)
		pcall(cluster.send, name, service, cmd, table.unpack(args))
	end)
end

function M.call_any(service, cmd, ...)
	local count = get_login_count()
	local last_err
	for i = 1, count do
		local name = M.cluster_name(i)
		local ok, ret = pcall(cluster.call, name, service, cmd, ...)
		if ok then
			return true, ret
		end
		last_err = ret
	end
	return false, last_err
end

return M
