local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local sharedata = require "skynet.sharedata"
local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"
local data_access = require "common.data_access"

-- _GATEWAY_PROC_ID用来回传消息到网关服
-- _ENTITY_ID用来标识玩家在gateway与world之间的会话ID
local _ACC_ID, _GATEWAY_PROC_ID, _ENTITY_ID, _SERVER_ID = ...
local const = nil


local _GLOABL = {}

local REQUEST = {}
local CMD = {}

local _CHECK_INTERVAL_TICK = 6 * 100 -- 6s
local _TICK_COUNT = 0
local _LAST_HEARTBEAT_TIME = 0


-- 模块列表
local _MODULE_LIST = {}
--模块加载流程
--1.world_agent启动时，加载所有模块文件
--2.模块初始化
--3.模块加载数据
--4.模块加载完成
--5.模块同步数据
--6.模块关闭

local function push_client(proto, data)
    logger.info("push_client, proto=%s, data=%s", proto, util.serialize(data))
    cluster.send(
        "gateway_" .. _SERVER_ID .. "_" .. _GATEWAY_PROC_ID,
        ".gateway_watchdog",
        "push_to_client",
        {
            entity_id = _ENTITY_ID,
            proto = proto,
            data = data,
        }
    )
end


local function close_modules()
    logger.info("close_modules _ENTITY_ID=%s", _ENTITY_ID)
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.close then
            mod.close()
        end
    end
end

local function sync_modules_data()
    logger.info("sync_modules_data _ENTITY_ID=%s", _ENTITY_ID)
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.sync_data then
            mod.sync_data()
        end
    end
end

local function check_heartbeat_timeout()
    if _LAST_HEARTBEAT_TIME and _LAST_HEARTBEAT_TIME ~= 0 and 
        os.time() - _LAST_HEARTBEAT_TIME > const.heartbeat_timeout then
        logger.error("heartbeat timeout, entity_id=%s", _ENTITY_ID)
        return true
    end
    return false
end

local function tick_modules()
    
    if check_heartbeat_timeout() then
        -- 心跳超时，断开连接
        -- 这里需要通知gateway
        cluster.send(
            "gateway_" .. _SERVER_ID .. "_" .. _GATEWAY_PROC_ID,
            ".gateway_watchdog",
            "player_disconnect",
            {
                entity_id = _ENTITY_ID,
            }
        )
        return
    end

    _TICK_COUNT = _TICK_COUNT + 1
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.tick then -- 6s 处理一次
            mod.tick()
        end
    end
    
    if _TICK_COUNT >= 10 then -- 6s * 10 = 60s
        _TICK_COUNT = 0
        -- 一分钟处理
        for _, mod in ipairs(_MODULE_LIST) do
            if mod.tick_one_minute then
                mod.tick_one_minute()
            end
        end
    end
end

--启动一个计时器
local function start_tick_timer()
    local function schedule()
        skynet.timeout(_CHECK_INTERVAL_TICK, function()
            tick_modules()
            schedule()
        end)
    end
    schedule()
end

local function load_modules_complete()
    logger.info("load_modules_complete _ENTITY_ID=%s", _ENTITY_ID)
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.load_complete then
            mod.load_complete()
        end
    end
end

local function init_modules()
    logger.info("init_modules _ENTITY_ID=%s", _ENTITY_ID)
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.init then
            mod.init(_GLOABL)
        end
    end
end

local function load_modules_data()
    logger.info("load_modules_data _ENTITY_ID=%s", _ENTITY_ID)
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.load_data then
            mod.load_data()
        end
    end
end

local function require_modules()
    logger.info("require_modules _ENTITY_ID=%s", _ENTITY_ID)
    local world_agent_module_sort = const.world_agent_module_sort
    for name, mod_sort in pairs(world_agent_module_sort) do
        local mod_name = const.world_agent_module[name]
        logger.info("require_modules name=%s, mod_name=%s, mod_sort=%s", name, mod_name, mod_sort)
        _MODULE_LIST[mod_sort] = require("world.service.agent." .. mod_name)
    end
end

function REQUEST:heartbeat_game()
    logger.info("heartbeatGame request, entity_id=%s", _ENTITY_ID)
    _LAST_HEARTBEAT_TIME = os.time()
    return {
            error_code = const.error_code.success,
            server_time = _LAST_HEARTBEAT_TIME,
        }
end

function REQUEST:show_world_agent_data()
    logger.info("showWorldAgentData request, entity_id=%s, data_desc=%s", _ENTITY_ID, data_desc)
    local result = ""
    local module_desc = self.module_desc
    local data_desc = self.data_desc
    local mod_sort = const.world_agent_module_sort[module_desc]
    if not mod_sort then
        return { error_code = const.error_code.invalid_params }
    end
    local mod = _MODULE_LIST[mod_sort]
    if not mod then
        return { error_code = const.error_code.invalid_params }
    end
    
    result = mod.showWorldAgentData(data_desc)
    push_client("update_world_agent_data_info", {
        result = result,
    })

    return { error_code = const.error_code.success }
end


function CMD.client_request(name, args)
    local f = REQUEST[name]
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.REQUEST and mod.REQUEST[name] then
            f = mod.REQUEST[name]
            break
        end
    end
    if not f then
        logger.error("world_agent unknown request, name=%s", name)
        return { error_code = const.error_code.unknown_proto }
    end
    return f(args)
end

function CMD.disconnect()
    logger.info("world_agent disconnect, acc_id=%s, entity_id=%s", _ACC_ID, _ENTITY_ID)
    
    logger.info("world_agent disconnect success, acc_id=%s, entity_id=%s, is_online=%s", _ACC_ID, _ENTITY_ID, data_access.is_online(_SERVER_ID, _ACC_ID))
    close_modules()
    skynet.exit()
end


function CMD.notify_world_0am_update()
    logger.info("notify_world_0am_update, entity_id=%s", _ENTITY_ID)
    if not _MODULE_LIST then
        return
    end
    
    for _, mod in ipairs(_MODULE_LIST) do
        if mod.onToday0am then
            mod.onToday0am()
        end
    end
end

function CMD.notify_world_6am_update()
    logger.info("notify_world_6am_update, entity_id=%s", _ENTITY_ID)
    if not _MODULE_LIST then
        return
    end

    for _, mod in ipairs(_MODULE_LIST) do
        if mod.onToday6am then
            mod.onToday6am()
        end
    end
end


skynet.init(function()
    const = sharedata.query "const"
    _ACC_ID = tonumber(_ACC_ID)
    _GATEWAY_PROC_ID = tonumber(_GATEWAY_PROC_ID)
    _ENTITY_ID = tonumber(_ENTITY_ID)
    _SERVER_ID = tonumber(_SERVER_ID)

    _GLOABL._ACC_ID = _ACC_ID
    _GLOABL._GATEWAY_PROC_ID = _GATEWAY_PROC_ID
    _GLOABL._ENTITY_ID = _ENTITY_ID
    _GLOABL._SERVER_ID = _SERVER_ID
    _GLOABL.push_client = push_client

    require_modules()
    logger.info("world agent initialized, acc_id=%s, entity_id=%s", _ACC_ID, _ENTITY_ID)
end)

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
        local args = {...}
        local ok, err = xpcall(function()
            if CMD[cmd] then
                snutil.lua_docmd(session, CMD, cmd, table.unpack(args))
            else
                for _, mod in ipairs(_MODULE_LIST) do
                    if mod.CMD and mod.CMD[cmd] then
                        snutil.lua_docmd(session, mod.CMD, cmd, table.unpack(args))
                        return
                    end
                end
            end
        end, snutil.handle_err)
        if not ok then
            logger.info(string.format("%s error, cmd=%s, session=%s, source=%s, args=%s",
                SERVICE_NAME, cmd, session, source, tostring(args)))
            error(err)
        end
	end)

    init_modules()
    load_modules_data()
    load_modules_complete()
    skynet.fork(function()
        skynet.sleep(100)
        sync_modules_data() -- 登录成功之后，同步数据给客户端
    end)

    start_tick_timer() -- 启动心跳计时器

	logger.info("world agent started")
end)


-- 加载角色全部背包格子
--local slots = data_access.load_many("bag_slots", { parentDBID = _ROLE_BASE.dbid })
--logger.info("init_player success, slots=%s", util.serialize(slots))

--[[
    -- 加载单个格子
    local slot_row = data_access.load("bag_slots", { parentDBID = _ROLE_BASE.dbid, index = 1 })

    -- 新增格子（先写 MySQL，再写缓存）
    data_access.insert("bag_slots", {
        parentDBID = _ROLE_BASE.dbid,
        index = 1,
        itemID = 10001,
        count = 10,
        data = {},
    })

    slot_row = data_access.load("bag_slots", { parentDBID = _ROLE_BASE.dbid, index = 1 })

    -- 修改格子（写缓存并标脏，data_sync 异步落库）
    data_access.save("bag_slots", slot_row)
--]]

--[[
    skynet.fork(function()
        skynet.sleep(1000)
        _ROLE_BASE.name = "xiaoming"
        _ROLE_DATA.moveSpeed = 100
        _ROLE_DATA.teamLevel = 2
        _ROLE_DATA.teamExp = 100
        data_access.save("role_base", _ROLE_BASE)
        data_access.save("role_data", _ROLE_DATA)
    end)

    skynet.fork(function()
        skynet.sleep(2000)
        _ROLE_BASE.name = "xiaoming"
        _ROLE_DATA.moveSpeed = 1001
        _ROLE_DATA.teamLevel = 22
        _ROLE_DATA.teamExp = 1000
        _ROLE_DATA.fightingValue = 10000
        _ROLE_DATA.schoolLevel = 10
        _ROLE_DATA.schoolExp = 1000
        _ROLE_DATA.militaryLv = 10
        data_access.save("role_base", _ROLE_BASE)
        data_access.save("role_data", _ROLE_DATA)
    end)
--]]
