local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local sharedata = require "skynet.sharedata"
local util = require "common.util"
local logger = require "common.logger"


local M = {}

local CMD = {}
local REQUEST = {}
local _GLOBAL = nil
local player = nil
local partner = nil
local const = nil



M.REQUEST = REQUEST
M.CMD = CMD

function M.init(global)
    _GLOBAL = global
    player = require "world.service.agent.player"
    partner = require "world.service.agent.partner"
    const = sharedata.query("const")
end

function M.load_data()

end

function M.load_complete()

end

function M.sync_data()

end

function M.tick()

end

function M.onToday0am()

end

function M.onToday6am()

end

function M.close()

end

function M.showWorldAgentData(data_desc)
    
    return "data not found"
end

-- 发起战斗
function REQUEST:start_fight()
    local fight_type = tonumber(self.fight_type)
    local server_id = tonumber(self.server_id)
    local fight_dbid = tonumber(self.fight_dbid)

    logger.info("start_fight, fight_type: %s, server_id: %s, fight_dbid: %s", fight_type, server_id, fight_dbid)

    if not fight_type or not server_id or not fight_dbid then
        return {error_code = const.error_code.invalid_params}
    end

    local my_fight_mirror_data = partner.get_partner_fight_mirror()
    local dest_fight_mirror_data = cluster.call(
        "worldMgr_" .. _GLOBAL._SERVER_ID .. "_1",
        ".role_data_transmit_mgr",
        "query_role_data",
        server_id,
        fight_dbid,
        "get_partner_fight_mirror"
    )

    if not dest_fight_mirror_data then
        logger.error("start_fight failed, server_id: %s, fight_dbid: %s, dest_fight_mirror_data: %s", server_id, fight_dbid, tostring(dest_fight_mirror_data))
        return {error_code = const.error_code.start_fight_failed}
    end

    logger.info("start_fight success, my_fight_mirror_data: %s", util.serialize(my_fight_mirror_data))
    logger.info("start_fight success, dest_fight_mirror_data: %s", util.serialize(dest_fight_mirror_data))

    local ok, battle_id = skynet.call(".fighting_mgr", "lua", "create_fighting", {
        fight_type = fight_type,
        my_server_id = _GLOBAL._SERVER_ID,
        my_dbid = player.get_role_base_dbid(),
        dest_server_id = server_id,
        dest_dbid = fight_dbid,
        attacker_mirror = my_fight_mirror_data,
        defender_mirror = dest_fight_mirror_data,
    })
    if not ok then
        logger.error("start_fight failed, create_fighting failed, battle_id: %s", battle_id)
        return {error_code = const.error_code.start_fight_failed}
    end

    logger.info("start_fight success, battle_id: %s", battle_id)
    local ok = skynet.call(".fighting_mgr", "lua", "do_fighting", {
        battle_id = battle_id,
    })
    if not ok then
        logger.error("start_fight failed, do_fighting failed, battle_id: %s", battle_id)
        return {error_code = const.error_code.start_fight_failed}
    end
    logger.info("start_fight success, do_fighting success, battle_id: %s", battle_id)

    return {error_code = const.error_code.success, battle_id = battle_id}
end

-- 结束战斗
function REQUEST:end_fight()
    local fight_type = self.fight_type
    local battle_id = self.battle_id
    if not fight_type or not battle_id then
        return {error_code = const.error_code.invalid_params}
    end
    
    logger.info("end_fight, fight_type: %s, battle_id: %s", fight_type, battle_id)
    
    return {error_code = const.error_code.success}
end


return M
