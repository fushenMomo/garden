local skynet = require "skynet"
require "skynet.manager"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"

local _FIGHTING_AGENT_LIST = {}
local _BATTLE_ID_SEQ = 0

local function gen_battle_id()
    _BATTLE_ID_SEQ = _BATTLE_ID_SEQ + 1
    return _BATTLE_ID_SEQ
end

local CMD = {}

function CMD.create_fighting(msg)
    logger.info("fighting_mgr create_fighting, msg=%s", util.serialize(msg))
    local fight_type = tonumber(msg.fight_type)
    local my_server_id = tonumber(msg.my_server_id)
    local my_dbid = tonumber(msg.my_dbid)
    local dest_server_id = tonumber(msg.dest_server_id)
    local dest_dbid = tonumber(msg.dest_dbid)
    local attacker_mirror = msg.attacker_mirror
    local defender_mirror = msg.defender_mirror
    if not fight_type or not my_server_id or not my_dbid or not dest_server_id or not dest_dbid or not attacker_mirror or not defender_mirror then
        logger.error("create_fighting failed, invalid params")
        return false
    end

    local battle_id = gen_battle_id()
    local fighting_agent = skynet.newservice("service/standalone/fighting")
    local ret = skynet.call(fighting_agent, "lua", "init_fighting", {
        battle_id = battle_id,
        fight_type = fight_type,
        my_server_id = my_server_id,
        my_dbid = my_dbid,
        dest_server_id = dest_server_id,
        dest_dbid = dest_dbid,
        attacker_mirror = attacker_mirror,
        defender_mirror = defender_mirror
    })
    if not ret then
        logger.error("create_fighting init_fighting failed, battle_id=%s", battle_id)
        skynet.kill(fighting_agent)
        return false
    end

    _FIGHTING_AGENT_LIST[battle_id] = fighting_agent
    logger.info("create_fighting success, battle_id=%s", battle_id)
    return true, battle_id
end


function CMD.do_fighting(msg)
    local battle_id = tonumber(msg.battle_id)
    local fighting_agent = _FIGHTING_AGENT_LIST[battle_id]
    if not fighting_agent then
        logger.error("do_fighting failed, battle_id=%s not found", battle_id)
        return false
    end
    return skynet.call(fighting_agent, "lua", "do_fighting", msg)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, CMD, cmd, ...)
    end)

    skynet.register(".fighting_mgr")
    logger.info("fighting_mgr started")
end)
