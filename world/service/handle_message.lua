local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local sharedata = require "skynet.sharedata"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local graceful_stop = require "common.graceful_stop"

local _SERVER_ID = nil
local _PROC_ID = nil
local _WORLD_MAXCLIENT = nil
local _AGENT_LIST = {}
local _ACC_ENTITY_MAP = {}
local _ROLE_DBID_ENTITY_MAP = {}
local _AGENT_COUNT = 0

local const

local CMD = {}

local function world_cluster_name()
    return "world_" .. _SERVER_ID .. "_" .. _PROC_ID
end

local function remove_agent(entity_id)
    entity_id = tonumber(entity_id)
    local agent = _AGENT_LIST[entity_id]
    if not agent then
        return false
    end
    for acc_id, eid in pairs(_ACC_ENTITY_MAP) do
        if eid == entity_id then
            _ACC_ENTITY_MAP[acc_id] = nil
            break
        end
    end
    _AGENT_LIST[entity_id] = nil
    for role_dbid, eid in pairs(_ROLE_DBID_ENTITY_MAP) do
        if eid == entity_id then
            _ROLE_DBID_ENTITY_MAP[role_dbid] = nil
        end
    end
    _AGENT_COUNT = math.max(0, _AGENT_COUNT - 1)
    skynet.send(agent, "lua", "disconnect")
    return true
end

function CMD.bind_role_entity(role_dbid, entity_id)
    role_dbid = tonumber(role_dbid)
    entity_id = tonumber(entity_id)
    if not role_dbid or not entity_id then
        return false
    end
    _ROLE_DBID_ENTITY_MAP[role_dbid] = entity_id
    return true
end

function CMD.unbind_role_entity(role_dbid)
    role_dbid = tonumber(role_dbid)
    if not role_dbid then
        return false
    end
    _ROLE_DBID_ENTITY_MAP[role_dbid] = nil
    return true
end

function CMD.agent_cmd_by_role_dbid(role_dbid, cmd, ...)
    role_dbid = tonumber(role_dbid)
    if not role_dbid or not cmd then
        return nil
    end
    local entity_id = _ROLE_DBID_ENTITY_MAP[role_dbid]
    if not entity_id then
        logger.error("agent_cmd_by_role_dbid entity not found, role_dbid=%s, cmd=%s", role_dbid, cmd)
        return nil
    end
    local agent = _AGENT_LIST[entity_id]
    if not agent then
        logger.error("agent_cmd_by_role_dbid agent not found, role_dbid=%s, entity_id=%s, cmd=%s",
            role_dbid, entity_id, cmd)
        return nil
    end
    local args = {...}
    return skynet.call(agent, "lua", cmd, table.unpack(args))
end

function CMD.account_login_world(msg)
    logger.info("CMD.account_login_world, msg=%s", util.serialize(msg))
    local acc_id = tonumber(msg.acc_id)
    local gateway_proc_id = tonumber(msg.gateway_proc_id)
    local entity_id = tonumber(msg.entity_id)
    logger.info("CMD.account_login_world, acc_id=%s, gateway_proc_id=%s, entity_id=%s", acc_id, gateway_proc_id, entity_id)

    if _AGENT_LIST[entity_id] then
        return { success = true, world_cluster_name = world_cluster_name() }
    end

    local old_entity_id = _ACC_ENTITY_MAP[acc_id]
    if old_entity_id and old_entity_id ~= entity_id then
        logger.info("CMD.account_login_world kick old session, acc_id=%s, old_entity_id=%s, entity_id=%s",
            acc_id, old_entity_id, entity_id)
        remove_agent(old_entity_id)
    end

    local world_agent = skynet.newservice("service/world_agent", acc_id, gateway_proc_id, entity_id, _SERVER_ID)
    if not world_agent then
        logger.error("CMD.account_login_world newservice failed, acc_id=%s, gateway_proc_id=%s, entity_id=%s", acc_id, gateway_proc_id, entity_id)
        return { success = false, world_cluster_name = nil }
    end
    _AGENT_LIST[entity_id] = world_agent
    _ACC_ENTITY_MAP[acc_id] = entity_id
    _AGENT_COUNT = _AGENT_COUNT + 1

    return { success = true, world_cluster_name = world_cluster_name() }
end

function CMD.client_request(entity_id, name, args)
    entity_id = tonumber(entity_id)
    local agent = _AGENT_LIST[entity_id]
    if not agent then
        logger.error("client_request agent not found, entity_id=%s, name=%s", entity_id, name)
        return { error_code = const.error_code.not_in_game }
    end
    return skynet.call(agent, "lua", "client_request", name, args)
end

function CMD.player_disconnect(entity_id)
    entity_id = tonumber(entity_id)
    logger.info("player_disconnect, entity_id=%s", entity_id)
    remove_agent(entity_id)
    return true
end


function CMD.notify_world_0am_update()
    logger.info("notify_world_0am_update")
    if _AGENT_LIST and next(_AGENT_LIST) then
        for entity_id, agent in pairs(_AGENT_LIST) do
            skynet.send(agent, "lua", "notify_world_0am_update")
        end
    end
end

function CMD.notify_world_6am_update()
    logger.info("notify_world_6am_update")
    if _AGENT_LIST and next(_AGENT_LIST) then
        for entity_id, agent in pairs(_AGENT_LIST) do
            skynet.send(agent, "lua", "notify_world_6am_update")
        end
    end
end

function CMD.graceful_stop()
    logger.info("world graceful_stop begin, agent_count=%s", _AGENT_COUNT)
    local agents = {}
    for _, agent in pairs(_AGENT_LIST) do
        agents[#agents + 1] = agent
    end
    for _, agent in ipairs(agents) do
        pcall(skynet.call, agent, "lua", "disconnect")
    end
    _AGENT_LIST = {}
    _ACC_ENTITY_MAP = {}
    _ROLE_DBID_ENTITY_MAP = {}
    _AGENT_COUNT = 0
    return graceful_stop.finish()
end

--@server_id
--@proc_id world服的进程ID
--@load_value 当前world服在线人数
--@over_load 是否过载 true:过载 false:不过载
local function sync_world_loading2worldMgr(server_id, proc_id, load_value, over_load)
	if server_id == nil or proc_id == nil or load_value == nil or over_load == nil then
		return false
	end
	server_id = tonumber(server_id)
	proc_id = tonumber(proc_id)
	load_value = tonumber(load_value)
	local dest_cluster_name = "worldMgr_" .. server_id .. "_" .. 1
	local ret = cluster.call(
                                dest_cluster_name,
                                ".handle_message",
                                "sync_world_loading",
                                proc_id,
                                load_value,
                                over_load
                            )
	return ret
end

--@server_id
--@proc_id
--@world_func_flag
local function sync_func_flag2worldMgr(server_id, proc_id, world_func_flag)
    local dest_cluster_name = "worldMgr_" .. server_id .. "_" .. 1
    local ret = cluster.call(
                                dest_cluster_name, 
                                ".handle_message", 
                                "register_world_func", 
                                proc_id, 
                                world_func_flag
                            )
    if not ret then
        logger.info("register_world_func failed, proc_id=%s, world_func_flag=%s", proc_id, world_func_flag)
    end
end

skynet.init(function()
    const = sharedata.query "const"
end)

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		snutil.xpcall_docmd(session, source, CMD, cmd, ...)
	end)

    _SERVER_ID = skynet.getenv("server_id")
    _PROC_ID = skynet.getenv("proc_id")
    _WORLD_MAXCLIENT = tonumber(skynet.getenv("world_maxclient"))
	skynet.register(".handle_message")

    local world_func_flag = skynet.getenv("WORLD_FUNC_FLAG")
    if not world_func_flag then 
        -- 普通world服需要同步负载信息
        skynet.fork(function()
            while true do
                local load_value = _AGENT_COUNT
                local over_load = false
                if load_value >= _WORLD_MAXCLIENT then
                    over_load = true
                end
                sync_world_loading2worldMgr(_SERVER_ID, _PROC_ID, load_value, over_load)
                skynet.sleep(100 * 60) -- 1分钟同步一次
            end
        end)
    else
        --sync_func_flag2worldMgr(_SERVER_ID, _PROC_ID, world_func_flag)
    end
    
	logger.info("world handle_message started")
end)
