local skynet = require "skynet"
local socket = require "skynet.socket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local logger = require "common.logger"
local router = require "webAPI.service.router"

local mode, protocol = ...
protocol = protocol or "http"

if mode == "agent" then

local SSLCTX_SERVER = nil

local function gen_interface(proto, fd)
	if proto == "http" then
		return {
			read = sockethelper.readfunc(fd),
			write = sockethelper.writefunc(fd),
		}
	elseif proto == "https" then
		local tls = require "http.tlshelper"
		if not SSLCTX_SERVER then
			SSLCTX_SERVER = tls.newctx()
			local certfile = skynet.getenv("certfile") or "./server-cert.pem"
			local keyfile = skynet.getenv("keyfile") or "./server-key.pem"
			SSLCTX_SERVER:set_cert(certfile, keyfile)
		end
		local tls_ctx = tls.newtls("server", SSLCTX_SERVER)
		return {
			init = tls.init_responsefunc(fd, tls_ctx),
			close = tls.closefunc(tls_ctx),
			read = tls.readfunc(fd, tls_ctx),
			write = tls.writefunc(fd, tls_ctx),
		}
	else
		error(string.format("Invalid protocol: %s", proto))
	end
end

local function write_json(write, status, body)
	local header = {
		["Content-Type"] = "application/json; charset=utf-8",
	}
	httpd.write_response(write, status, body, header)
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, fd, addr)
		socket.start(fd)
		local interface = gen_interface(protocol, fd)
		if interface.init then
			interface.init()
		end

		local body_limit = tonumber(skynet.getenv("http_body_limit")) or 65536
		local code, url, method, header, body = httpd.read_request(interface.read, body_limit)
		if not code then
			if url ~= sockethelper.socket_error then
				logger.error("http read_request failed, fd=%s err=%s", fd, tostring(url))
			end
		elseif code ~= 200 then
			write_json(interface.write, code, string.format('{"code":%d,"msg":"http error"}', code))
		else
			-- 这段代码是处理收到的HTTP请求进行路由并返回结果的核心逻辑。
			-- 1. 利用 urllib.parse 解析 url，得到 path 和查询字符串 query_str。
			local path, query_str = urllib.parse(url)
			-- 2. 如果有查询字符串，用 urllib.parse_query 进一步解析为表，否则 query 是空表。
			local query = query_str and urllib.parse_query(query_str) or {}
			-- 3. 用 pcall 安全调用 router.dispatch 进行请求分派，获得 HTTP 状态码和响应体。
			local ok, status, resp = pcall(router.dispatch, method, path, query, body or "", header, addr)
			-- 4. 如果路由派发过程出错，记录日志，并返回 500 错误。
			if not ok then
				logger.error("router dispatch error, path=%s err=%s", path, status)
				write_json(interface.write, 500, '{"code":500,"msg":"internal error"}')
			else
				-- 5. 如果没有出错，则将结果通过 write_json 写回客户端，状态码默认 200，resp 为空则提供一个默认响应。
				write_json(interface.write, status or 200, resp or '{"code":0,"msg":"ok"}')
			end
		end

		socket.close(fd)
		if interface.close then
			interface.close()
		end
	end)
end)

end
