local skynet = require "skynet"
require "skynet.manager"

local logger = require "common.logger"
local snutil = require "common.snutil"
local util = require "common.util"

local _BATTLE_ID = nil
local _FIGHT_TYPE = nil
local _MY_SERVER_ID = nil
local _MY_DBID = nil
local _DEST_SERVER_ID = nil
local _DEST_DBID = nil
local _ATTACKER_MIRROR = nil
local _DEFENDER_MIRROR = nil

local CMD = {}

function CMD.init_fighting(msg)
    logger.info("fighting init_fighting, msg=%s", util.serialize(msg))
    local battle_id = tonumber(msg.battle_id)
    local fight_type = tonumber(msg.fight_type)
    local my_server_id = tonumber(msg.my_server_id)
    local my_dbid = tonumber(msg.my_dbid)
    local dest_server_id = tonumber(msg.dest_server_id)
    local dest_dbid = tonumber(msg.dest_dbid)
    local attacker_mirror = msg.attacker_mirror
    local defender_mirror = msg.defender_mirror
    if not battle_id or not fight_type or not my_server_id or not my_dbid or not dest_server_id or not dest_dbid or not attacker_mirror or not defender_mirror then
        logger.error("init_fighting failed, invalid params")
        return false
    end

    _BATTLE_ID = battle_id
    _FIGHT_TYPE = fight_type
    _MY_SERVER_ID = my_server_id
    _MY_DBID = my_dbid
    _DEST_SERVER_ID = dest_server_id
    _DEST_DBID = dest_dbid
    _ATTACKER_MIRROR = attacker_mirror
    _DEFENDER_MIRROR = defender_mirror

    skynet.register(".fighting_" .. _BATTLE_ID)
    logger.info("init_fighting success, battle_id=%s", _BATTLE_ID)
    return true
end

function CMD.do_fighting(msg)
    if not _BATTLE_ID then
        logger.error("do_fighting failed, not initialized")
        return false
    end

    logger.info("do_fighting, battle_id=%s, fight_type=%s, msg=%s", _BATTLE_ID, _FIGHT_TYPE, util.serialize(msg or {}))

    return {
        win = false,
        battle_id = _BATTLE_ID,
    }
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        snutil.xpcall_docmd(session, source, CMD, cmd, ...)
    end)

    logger.info("fighting service started")
end)
