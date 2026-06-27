#!/usr/bin/env lua
local script_dir = arg[0]:match("(.+[\\/])") or "./"
local root = script_dir .. "../"
local etc = root .. "etc/"
local tmpl_dir = etc .. "templates/"

local mode = arg[1]

local function read_file(path)
	local f = io.open(path, "r")
	if not f then error("open fail: " .. path) end
	local s = f:read("*a")
	f:close()
	return s
end

local function write_file(path, content)
	local f = io.open(path, "w")
	if not f then error("write fail: " .. path) end
	f:write(content)
	f:close()
end

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function parse_scalar(v)
	v = trim(v)
	v = v:match("^([^#]*)") or v
	v = trim(v)
	if v:sub(1, 1) == '"' and v:sub(-1) == '"' then
		return v:sub(2, -2)
	end
	if v == "true" then return true end
	if v == "false" then return false end
	local n = tonumber(v)
	if n then return n end
	return v
end

local function parse_yaml(text)
	local stack = { { t = "map", v = {} } }
	local indent_of = {}
	for line in text:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and trim(line) ~= "" then
			local indent = #line:match("^(%s*)")
			local content = trim(line)
			while #stack > 1 and indent <= (indent_of[#indent_of] or -1) do
				table.remove(stack)
				table.remove(indent_of)
			end
			local top = stack[#stack]
			if content:sub(1, 2) == "- " then
				if top.t ~= "list" then
					local parent = stack[#stack - 1]
					local key = top.for_key or (parent and parent.last_key)
					if not key then error("list without key: " .. line) end
					parent.v[key] = {}
					stack[#stack] = { t = "list", v = parent.v[key] }
					top = stack[#stack]
				end
				local val = trim(content:sub(3))
				if val:find(":") then
					local item = {}
					table.insert(top.v, item)
					stack[#stack + 1] = { t = "map", v = item }
					indent_of[#indent_of + 1] = indent
					local k, v = val:match("^([^:]+):%s*(.*)$")
					if k then item[trim(k)] = parse_scalar(v) end
				else
					table.insert(top.v, parse_scalar(val))
				end
			else
				local k, v = content:match("^([^:]+):%s*(.*)$")
				if not k then error("bad line: " .. line) end
				k = trim(k)
				if v == "" then
					top.v[k] = {}
					top.last_key = k
					stack[#stack + 1] = { t = "map", v = top.v[k], for_key = k }
					indent_of[#indent_of + 1] = indent
				else
					top.v[k] = parse_scalar(v)
				end
			end
		end
	end
	return stack[1].v
end

local tmpl_cache = {}
local function load_tmpl(name)
	if not tmpl_cache[name] then
		tmpl_cache[name] = read_file(tmpl_dir .. name .. ".tmpl")
	end
	return tmpl_cache[name]
end

local function render(tmpl, ctx)
	return (tmpl:gsub("{{([^}]+)}}", function(key)
		local v = ctx[key]
		if v == nil then error("missing template key: " .. key) end
		return tostring(v)
	end))
end

local T = parse_yaml(read_file(etc .. "topology.yaml"))
local host = T.host
local login_count = T.global.login.count
local groups = T.groups
local P = T.ports
local SK = T.skynet
local PROC = T.process
local DB = T.db
local REDIS = T.redis
local mysql_port = P.mysql or DB.login.port

local nodes = {}
local order = {}
local port_used = {}

local function track_port(kind, name, port)
	if not port then return end
	local key = kind .. ":" .. port
	if port_used[key] then
		error(string.format("port conflict %d (%s vs %s)", port, port_used[key], name))
	end
	port_used[key] = name
end

local function add_node(name, info)
	nodes[name] = info
	order[#order + 1] = name
	track_port("cluster", name, info.cluster)
	track_port("tcp", name, info.tcp)
	track_port("debug", name, info.debug)
end

local function gw_idx(sid, pid)
	local n = 0
	for _, g in ipairs(groups) do
		if g.id < sid then
			n = n + g.gateway_count
		elseif g.id == sid then
			return n + pid
		end
	end
end

local function world_idx(sid, pid)
	local n = 0
	for _, g in ipairs(groups) do
		if g.id < sid then
			n = n + g.world_count
		elseif g.id == sid then
			return n + pid
		end
	end
end

local function group_redis_port(sid)
	return P.redis.group_base + sid - 1
end

local Port = {}

function Port.cluster_worldmgr(sid)
	local base = P.cluster.worldmgr_base
	if sid <= 2 then return base + sid - 1 end
	local total_gw = 0
	for _, g in ipairs(groups) do
		total_gw = total_gw + g.gateway_count
	end
	return P.cluster.gateway_base + total_gw + (sid - 3)
end

function Port.cluster_world(sid, pid)
	local idx = world_idx(sid, pid)
	local extra = 0
	if sid >= 3 then
		for _, g in ipairs(groups) do
			if g.id < sid and g.bi then extra = extra + 1 end
		end
	end
	return P.cluster.world_base + idx - 1 + extra
end

function Port.cluster_bi(sid)
	if sid <= 2 then return P.cluster.bi_base + sid - 1 end
	local mx = P.cluster.bi_base
	for _, g in ipairs(groups) do
		for p = 1, g.world_count do
			mx = math.max(mx, Port.cluster_world(g.id, p))
		end
		if g.bi and g.id < sid then
			mx = math.max(mx, P.cluster.bi_base + g.id - 1)
		end
	end
	return mx + 1
end

function Port.debug_worldmgr(sid)
	if sid <= 2 then return P.debug_console.worldmgr_base + sid - 1 end
	return P.debug_console.worldmgr_base + sid + 2
end

add_node("serverMgr", { kind = "serverMgr", cluster = P.cluster.servermgr, debug = P.debug_console.servermgr })

for i = 1, login_count do
	add_node("login_" .. i, {
		kind = "login", proc_id = i,
		cluster = P.cluster.login_base + i - 1,
		tcp = P.tcp.login_base + (i - 1) * P.tcp.login_step,
		debug = P.debug_console.login_base + i - 1,
		redis_port = P.redis.login,
	})
end

add_node("webAPI", { kind = "webAPI", cluster = P.cluster.webapi, tcp = P.tcp.webapi, debug = P.debug_console.webapi })

for _, g in ipairs(groups) do
	local sid = g.id
	local redis_port = g.redis_port or group_redis_port(sid)
	for p = 1, g.gateway_count do
		local idx = gw_idx(sid, p)
		add_node(string.format("gateway_%d_%d", sid, p), {
			kind = "gateway", server_id = sid, proc_id = p,
			cluster = P.cluster.gateway_base + idx - 1,
			tcp = P.tcp.gateway_base + idx - 1,
			debug = P.debug_console.gateway_base + idx,
		})
	end
	add_node(string.format("worldMgr_%d_1", sid), {
		kind = "worldMgr", server_id = sid, proc_id = 1,
		cluster = Port.cluster_worldmgr(sid),
		debug = Port.debug_worldmgr(sid),
		redis_port = redis_port,
		gateway_count = g.gateway_count,
	})
	if g.bi then
		local wmd = Port.debug_worldmgr(sid)
		add_node(string.format("bi_%d_1", sid), {
			kind = "bi", server_id = sid, proc_id = 1,
			cluster = Port.cluster_bi(sid),
			debug = sid <= 2 and (wmd + P.debug_console.bi_offset) or (wmd + 1),
			redis_port = redis_port,
		})
	end
	for p = 1, g.world_count do
		local idx = world_idx(sid, p)
		add_node(string.format("world_%d_%d", sid, p), {
			kind = "world", server_id = sid, proc_id = p,
			cluster = Port.cluster_world(sid, p),
			debug = P.debug_console.world_base + idx,
			redis_port = redis_port,
		})
	end
end

local function addr(name)
	return string.format('%s = "%s:%d"', name, host, nodes[name].cluster)
end

local function same_group(name, sid)
	local a, b = name:match("^(%a+)_(%d+)_")
	if not a then return false end
	return tonumber(b) == sid
end

local function visible(owner, target)
	if owner == target then return true end
	local o = nodes[owner]
	local t = nodes[target]
	if not o or not t then return false end
	local okind, tk = o.kind, t.kind
	local sid = o.server_id
	if okind == "login" then
		return tk == "gateway" or tk == "worldMgr" or tk == "serverMgr" or tk == "login"
	elseif okind == "serverMgr" then
		return tk == "login" or tk == "worldMgr" or tk == "serverMgr"
	elseif okind == "webAPI" then
		return tk ~= "bi"
	elseif okind == "gateway" then
		if tk == "login" or tk == "serverMgr" then return true end
		if same_group(target, sid) and (tk == "gateway" or tk == "world" or tk == "worldMgr" or tk == "bi") then return true end
	elseif okind == "world" then
		if tk == "login" or tk == "serverMgr" then return true end
		if same_group(target, sid) and (tk == "gateway" or tk == "world" or tk == "worldMgr" or tk == "bi") then return true end
	elseif okind == "worldMgr" then
		if tk == "login" or tk == "serverMgr" then return true end
		if same_group(target, sid) and (tk == "gateway" or tk == "world" or tk == "worldMgr") then return true end
	elseif okind == "bi" then
		if tk == "login" or tk == "serverMgr" or target == owner then return true end
		if same_group(target, sid) and (tk == "gateway" or tk == "world") then return true end
	end
	return false
end

local function cluster_file(owner)
	local lines = {}
	for _, name in ipairs(order) do
		if visible(owner, name) then
			lines[#lines + 1] = addr(name)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

local function skynet_ctx(cfg)
	return {
		thread = SK.thread,
		harbor = SK.harbor,
		start = cfg.start,
		bootstrap = SK.bootstrap,
		luaservice = cfg.luaservice,
		lualoader = SK.lualoader,
		lua_path = SK.lua_path,
		lua_cpath = SK.lua_cpath,
		cpath = SK.cpath,
	}
end

local function db_login_ctx()
	return {
		db_login_name = DB.login.name,
		db_login_host = DB.login.host,
		db_login_port = mysql_port,
		db_login_user = DB.login.user,
		db_login_password = DB.login.password,
	}
end

local function db_game_ctx()
	return {
		db_game_name = DB.game.name,
		db_game_host = DB.game.host,
		db_game_port = mysql_port,
		db_game_user = DB.game.user,
		db_game_password = DB.game.password,
	}
end

local function db_global_ctx()
	return {
		db_global_name = DB.global.name,
		db_global_host = DB.global.host,
		db_global_port = mysql_port,
		db_global_user = DB.global.user,
		db_global_password = DB.global.password,
	}
end

local function redis_ctx(port)
	return {
		redis_host = REDIS.host,
		redis_port = port,
		redis_password = REDIS.password,
		redis_db_index = REDIS.db_index,
	}
end

local function merge_ctx(base, extra)
	for k, v in pairs(extra) do base[k] = v end
	return base
end

local function build_ctx(name, n)
	local cfg = PROC[n.kind]
	local ctx = merge_ctx({ name = name, logger_level = SK.logger_level }, skynet_ctx(cfg))
	ctx.skynet = render(load_tmpl("_skynet"), ctx)

	if n.kind == "login" or n.kind == "serverMgr" or n.kind == "bi" then
		ctx.db_login = render(load_tmpl("_db_login"), merge_ctx({}, db_login_ctx()))
	end
	if n.kind == "world" or n.kind == "worldMgr" then
		ctx.db_game = render(load_tmpl("_db_game"), merge_ctx({}, db_game_ctx()))
		ctx.db_global = render(load_tmpl("_db_global"), merge_ctx({}, db_global_ctx()))
	end
	if n.kind == "login" then
		ctx.redis = render(load_tmpl("_redis"), merge_ctx({}, redis_ctx(P.redis.login)))
	elseif n.kind == "world" or n.kind == "worldMgr" or n.kind == "bi" then
		ctx.redis = render(load_tmpl("_redis"), merge_ctx({}, redis_ctx(n.redis_port)))
	end

	ctx.debug_port = n.debug
	ctx.login_count = login_count

	if n.proc_id then ctx.proc_id = n.proc_id end
	if n.server_id then ctx.server_id = n.server_id end
	if n.tcp then ctx.tcp_port = n.tcp end

	if n.kind == "login" then
		ctx.login_maxclient = cfg.login_maxclient
		ctx.login_package_max = cfg.login_package_max
	elseif n.kind == "gateway" then
		ctx.gateway_maxclient = cfg.gateway_maxclient
		ctx.gateway_package_max = cfg.gateway_package_max
	elseif n.kind == "world" then
		ctx.world_maxclient = cfg.world_maxclient
		if n.proc_id == PROC.worldMgr.guild_world_proc_id then
			ctx.world_func_flag = '\nWORLD_FUNC_FLAG = "guild"'
		else
			ctx.world_func_flag = ""
		end
	elseif n.kind == "webAPI" then
		ctx.http_protocol = cfg.http_protocol
		ctx.http_agent_count = cfg.http_agent_count
		ctx.http_body_limit = cfg.http_body_limit
		ctx.web_api_key = cfg.web_api_key
	elseif n.kind == "worldMgr" then
		ctx.gateway_count = n.gateway_count
		ctx.guild_world_proc_id = cfg.guild_world_proc_id
	end

	for k, v in pairs(ctx) do
		if v == "" then ctx[k] = "" end
	end
	return ctx
end

local function config_file(name, n)
	local ctx = build_ctx(name, n)
	local body = render(load_tmpl(n.kind), ctx)
	return body:gsub("\n\n\n+", "\n\n") .. "\n"
end

local function dump_ports()
	print(string.format("%-20s %8s %8s %8s %8s", "name", "cluster", "tcp", "debug", "redis"))
	for _, name in ipairs(order) do
		local n = nodes[name]
		print(string.format("%-20s %8s %8s %8s %8s",
			name,
			tostring(n.cluster or "-"),
			tostring(n.tcp or "-"),
			tostring(n.debug or "-"),
			tostring(n.redis_port or "-")))
	end
end

if mode == "--dump-ports" then
	dump_ports()
	return
end

if mode == "--check" then
	print("port check ok: " .. #order .. " processes")
	return
end

local function pid_entry(name, n)
	return string.format("skynet_%s:log/%s/%s.pid", name, n.kind, name)
end

local function collect_by_kind(kind)
	local list = {}
	for _, nm in ipairs(order) do
		if nodes[nm].kind == kind then
			list[#list + 1] = pid_entry(nm, nodes[nm])
		end
	end
	return list
end

local function sh_lines(list)
	local lines = {}
	for _, item in ipairs(list) do
		lines[#lines + 1] = '    "' .. item .. '"'
	end
	return lines
end

local function write_array_sh(path, header, arrays, footer)
	local sh = { "#!/bin/bash", "" }
	for _, block in ipairs(header) do
		sh[#sh + 1] = block
	end
	sh[#sh + 1] = ""
	for _, arr in ipairs(arrays) do
		sh[#sh + 1] = arr.name .. "=("
		for _, line in ipairs(sh_lines(arr.list)) do
			sh[#sh + 1] = line
		end
		sh[#sh + 1] = ")"
		sh[#sh + 1] = ""
	end
	if footer then
		for _, line in ipairs(footer) do
			sh[#sh + 1] = line
		end
	end
	write_file(path, table.concat(sh, "\n") .. "\n")
end

for _, name in ipairs(order) do
	write_file(etc .. "clustername." .. name, cluster_file(name))
	write_file(etc .. "config." .. name, config_file(name, nodes[name]))
end

local sh = { "#!/bin/bash", "", "cd ./skynet", "", "SERVICES=(" }
for _, name in ipairs(order) do
	sh[#sh + 1] = "    " .. name
end
sh[#sh + 1] = ")"
sh[#sh + 1] = ""
sh[#sh + 1] = 'for name in "${SERVICES[@]}"; do'
sh[#sh + 1] = '    bash -c "exec -a skynet_${name} ./skynet ../etc/config.${name}"'
sh[#sh + 1] = '    echo "start ${name} ..."'
sh[#sh + 1] = "    sleep 2"
sh[#sh + 1] = "done"
write_file(root .. "start.sh", table.concat(sh, "\n") .. "\n")

local gateway_list = collect_by_kind("gateway")
local world_list = collect_by_kind("world")
local worldmgr_list = collect_by_kind("worldMgr")
local other_list = {}
for _, name in ipairs(order) do
	local k = nodes[name].kind
	if k == "bi" or k == "webAPI" or k == "login" or k == "serverMgr" then
		other_list[#other_list + 1] = pid_entry(name, nodes[name])
	end
end

local kill_list = {}
for _, list in ipairs({ gateway_list, world_list, worldmgr_list }) do
	for _, item in ipairs(list) do kill_list[#kill_list + 1] = item end
end
for _, item in ipairs(other_list) do kill_list[#kill_list + 1] = item end

write_array_sh(root .. "kill.sh", {
	[[get_pid() {
    local tag=$1
    local pidfile=$2
    local pid=""
    if [ -n "$pidfile" ] && [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile" 2>/dev/null)
    fi
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        return 0
    fi
    pid=$(pgrep -f "$tag" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi
    return 1
}]],
	[[kill_one() {
    local tag=$1
    local pidfile=$2
    local pid
    pid=$(get_pid "$tag" "$pidfile") || {
        echo "$tag is not running."
        return 0
    }
    echo "kill -9 $tag (pid=$pid) ..."
    kill -9 "$pid" 2>/dev/null || true
}]],
}, {
	{ name = "ALL_LIST", list = kill_list },
}, {
	'for item in "${ALL_LIST[@]}"; do',
	'    kill_one "${item%%:*}" "${item#*:}"',
	"done",
	"",
	'for pid in $(pgrep -f "skynet_" 2>/dev/null); do',
	'    kill -9 "$pid" 2>/dev/null || true',
	"done",
	"",
	'for item in "${ALL_LIST[@]}"; do',
	'    tag=${item%%:*}',
	'    if pgrep -f "$tag" >/dev/null 2>&1; then',
	'        echo "$tag still running."',
	'        exit 1',
	'    fi',
	"done",
	"",
	'echo "all skynet processes killed."',
	"exit 0",
})

write_array_sh(root .. "stop.sh", {
	"GRACEFUL_TIMEOUT=30",
	[[get_pid() {
    local tag=$1
    local pidfile=$2
    local pid=""
    if [ -n "$pidfile" ] && [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile" 2>/dev/null)
    fi
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        return 0
    fi
    pid=$(pgrep -f "$tag" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi
    return 1
}]],
	[[graceful_stop_one() {
    local tag=$1
    local pidfile=$2
    local pid
    pid=$(get_pid "$tag" "$pidfile") || {
        echo "$tag is not running."
        return 0
    }

    echo "graceful stopping $tag (pid=$pid) ..."
    kill -USR1 "$pid" 2>/dev/null || true
    local i=0
    while [ "$i" -lt "$GRACEFUL_TIMEOUT" ]; do
        kill -0 "$pid" 2>/dev/null || {
            echo "$tag stopped."
            return 0
        }
        sleep 1
        i=$((i + 1))
    done

    echo "force stopping $tag ..."
    kill "$pid" 2>/dev/null || true
}]],
	[[force_stop_one() {
    local tag=$1
    local pidfile=$2
    local pid
    pid=$(get_pid "$tag" "$pidfile") || return 0
    kill -9 "$pid" 2>/dev/null || true
}]],
}, {
	{ name = "GATEWAY_LIST", list = gateway_list },
	{ name = "WORLD_LIST", list = world_list },
	{ name = "WORLDMGR_LIST", list = worldmgr_list },
	{ name = "OTHER_LIST", list = other_list },
}, {
	"HAS_RUNNING=0",
	"STOP_FAILED=0",
	"",
	'for item in "${GATEWAY_LIST[@]}" "${WORLD_LIST[@]}" "${WORLDMGR_LIST[@]}" "${OTHER_LIST[@]}"; do',
	'    tag=${item%%:*}',
	'    if pgrep -f "$tag" >/dev/null 2>&1; then',
	"        HAS_RUNNING=1",
	"        break",
	"    fi",
	"done",
	"",
	'if [ "$HAS_RUNNING" -eq 0 ]; then',
	'    echo "no skynet process running."',
	"    exit 0",
	"fi",
	"",
	'for item in "${GATEWAY_LIST[@]}"; do',
	'    graceful_stop_one "${item%%:*}" "${item#*:}"',
	"done",
	"",
	'for item in "${WORLD_LIST[@]}"; do',
	'    graceful_stop_one "${item%%:*}" "${item#*:}"',
	"done",
	"",
	"sleep 1",
	"",
	'for item in "${WORLDMGR_LIST[@]}"; do',
	'    graceful_stop_one "${item%%:*}" "${item#*:}"',
	"done",
	"",
	'for item in "${OTHER_LIST[@]}"; do',
	'    graceful_stop_one "${item%%:*}" "${item#*:}"',
	"done",
	"",
	"sleep 1",
	"",
	'ALL_LIST=("${GATEWAY_LIST[@]}" "${WORLD_LIST[@]}" "${WORLDMGR_LIST[@]}" "${OTHER_LIST[@]}")',
	'for item in "${ALL_LIST[@]}"; do',
	'    tag=${item%%:*}',
	'    pidfile=${item#*:}',
	'    pid=$(get_pid "$tag" "$pidfile" 2>/dev/null) || continue',
	'    if kill -0 "$pid" 2>/dev/null; then',
	'        echo "$tag still running, force kill ..."',
	'        force_stop_one "$tag" "$pidfile"',
	"        STOP_FAILED=1",
	"    fi",
	"done",
	"",
	'for item in "${ALL_LIST[@]}"; do',
	'    tag=${item%%:*}',
	'    if pgrep -f "$tag" >/dev/null; then',
	'        echo "$tag still running after force kill."',
	"        STOP_FAILED=1",
	"    else",
	'        echo "$tag stopped."',
	"    fi",
	"done",
	"",
	'if [ "$STOP_FAILED" -eq 1 ]; then',
	"    exit 1",
	"fi",
	"exit 0",
})

print("gen ok: " .. #order .. " processes")
