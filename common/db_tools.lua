local skynet = require "skynet"
require "skynet.manager"
local const = require "common.const"
local data_access = require "common.data_access"

local M = {}

--@server_id
--@acc_id
function M.is_player_online(server_id, acc_id)
    return data_access.is_online(server_id, acc_id)
end

--@acc_id
--@server_id
--@opts.memory 在线时传入 L1 内存数据，优先返回
function M.load_player_data(acc_id, server_id, opts)
    acc_id = tonumber(acc_id)
    server_id = tonumber(server_id)
    if not acc_id or not server_id then
        return false
    end
    return data_access.load("player_data", { act_id = acc_id, server_id = server_id }, opts)
end

--@acc_id
--@server_id
function M.insert_player_data(acc_id, server_id)
    acc_id = tonumber(acc_id)
    server_id = tonumber(server_id)
    if not acc_id or not server_id then
        return false
    end
    local ok = data_access.insert("player_data", {
        act_id = acc_id,
        server_id = server_id,
        create_time = os.time(),
    })
    return ok
end

--@acc_id
--@server_id
--@data
function M.update_player_data(acc_id, server_id, data)
    acc_id = tonumber(acc_id)
    server_id = tonumber(server_id)
    if not acc_id or not server_id or not data then
        return false
    end
    data.actID = acc_id
    data.serverID = server_id
    return data_access.save("player_data", data)
end

--@dbid
--@opts.memory 在线时传入 L1 内存数据
function M.load_role_base(dbid, opts)
    dbid = tonumber(dbid)
    if not dbid then
        return false
    end
    return data_access.load("role_base", { dbid = dbid }, opts)
end

--@parent_dbid
--@opts.memory
function M.load_role_data(parent_dbid, opts)
    parent_dbid = tonumber(parent_dbid)
    if not parent_dbid then
        return false
    end
    return data_access.load("role_data", { parent_dbid = parent_dbid }, opts)
end

--@act_id
--@server_id
function M.insert_role_base(act_id, server_id)
    act_id = tonumber(act_id)
    server_id = tonumber(server_id)
    if not act_id or not server_id then
        return false
    end

    local ok, dbid = data_access.insert("role_base", {
        act_id = act_id,
        server_id = server_id,
        create_time = os.time(),
        sex = const.sex.boy,
        name = "test_role_" .. act_id,
    })
    if not ok or not dbid then
        return false
    end

    data_access.insert("role_data", { parent_dbid = dbid })
    data_access.insert("role_guild", { parent_dbid = dbid })
    return dbid
end

--@dbid
--@data
function M.update_role_base(dbid, data)
    dbid = tonumber(dbid)
    if not dbid or not data then
        return false
    end
    data.dbid = dbid
    return data_access.save("role_base", data)
end


function M.insert_role_data(parent_dbid)
    parent_dbid = tonumber(parent_dbid)
    if not parent_dbid then
        return false
    end
    return data_access.insert("role_data", { parent_dbid = parent_dbid })
end

--@parent_dbid
--@data
function M.update_role_data(parent_dbid, data)
    parent_dbid = tonumber(parent_dbid)
    if not parent_dbid or not data then
        return false
    end
    data.parentDBID = parent_dbid
    return data_access.save("role_data", data)
end

function M.load_role_guild(parent_dbid, opts)
    parent_dbid = tonumber(parent_dbid)
    if not parent_dbid then
        return false
    end
    return data_access.load("role_guild", { parent_dbid = parent_dbid }, opts)
end

function M.insert_role_guild(parent_dbid)
    parent_dbid = tonumber(parent_dbid)
    if not parent_dbid then
        return false
    end
    return data_access.insert("role_guild", { parent_dbid = parent_dbid })
end

function M.update_role_guild(parent_dbid, data)
    parent_dbid = tonumber(parent_dbid)
    if not parent_dbid or not data then
        return false
    end
    data.parentDBID = parent_dbid
    return data_access.save("role_guild", data)
end

return M