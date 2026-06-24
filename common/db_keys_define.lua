
local DBDef = {}

DBDef.DataType = {  -- lua层的数据类型
	number = 1,
	table = 2,
	string = 3,
    json = 4,
}

local t = DBDef.DataType

DBDef.dbidBase = 10518
DBDef.tableIndexBase = 1
-- actBase 字段表示 act_id（账号ID）的起始基数，
--在相关的数据表（如 player_data）中作为分表或ID分配的基准值。
DBDef.actBase = 1018168

--[[
expandThreshold字段的含义：
expandThreshold 表示"触发分表扩容的阈值"。
当主表（比如 role_base）中最大的 dbid 值距离
当前分表最大容量(sharding * 表索引)不足 expandThreshold 时，
会提前自动创建下一个分表，保证玩家注册不会因为达到分表上限而阻塞。

这个字段是可以修改的（比如根据实际业务量调整），但修改后建议重启服务/进程，使新配置生效。
]]
DBDef.roleShardExpand = {
	sharding = 500 * 10000,              -- 每张表的数据容量阈值
	expandThreshold = 10000,             -- 提前扩容的新表的预留阈值，可根据业务需求调整
	primary = "role_base",               -- 主分表名
	tables = { "role_base", "role_data", "role_guild", "bag" }, -- 需要同时分表的表
}

DBDef.Table = {

    player = {
		-------------------------------------------------------------------------
		-- player_data
		-------------------------------------------------------------------------
		player_data = {
			tableName = "player_data",
			field = {
				"act_id", "server_id", "online", "online_time", "select_role",
				"role_1", "role_2", "role_3", "role_4", "shutup", 
				"create_time",
			},
			dataType = {
				t.number, t.number, t.number, t.number, t.number,
				t.number, t.number, t.number, t.number, t.number,
				t.number
			},
			sharding = 500*10000,
			shardKey = "act_id",
			queryKey = 1,
			updateKey = {1, 2},
			redisKey = function(row)
				return string.format("p:%s:%s", row.server_id, row.act_id)
			end,
			updateIndex = 3,
			limit = 1,
			keyMap = {
				act_id = "actID",
				server_id = "serverID",
				online_time = "onlineTime",
				select_role = "selectRole",
				role_1 = "role1",
				role_2 = "role2",
				role_3 = "role3",
				role_4 = "role4",
				create_time = "createTime",
			},
		},
	}, -- player

    role = {
        -------------------------------------------------------------------------
		-- role_base
		-------------------------------------------------------------------------
		role_base = {
			tableName = "role_base",  -- 表名
			field = {  -- 字段名
				"dbid", "act_id", "server_id", "name", "create_time",
				"sex",
			},
			dataType = {  -- 字段类型
				t.number, t.number, t.number, t.string, t.number,
				t.number,
			},
			sharding = 500*10000,		-- 分表间隔长度
			shardKey = "dbid",
			queryKey = 1,  -- 查询key，在field的index
			updateKey = {1}, -- 更新key
			redisKey = function(row)
				return string.format("rbase:%s", row.dbid)
			end,
			updateIndex = 3,  -- 更新数据的开始索引
			limit = 1,  -- 查询记录限制，有固定数量的才填
			--config = "cfg_name", -- redisKey的组合需要配置则填，不需要就不填
			keyMap = {	-- 将db的字段名转为lua逻辑使用的字段名
				act_id = "actID",
				create_time = "createTime",
				server_id = "serverID",
			},
		},

		-------------------------------------------------------------------------
		-- role_data
		-------------------------------------------------------------------------
		role_data = {
			tableName = "role_data",
			field = {
				"parent_dbid", "move_speed", "team_level", "team_exp", "fighting_value",
				"school_level", "school_exp", "military_lv",
			},
			dataType = {
				t.number, t.number, t.number, t.number, t.number,
				t.number, t.number, t.number,
			},
			sharding = 500*10000,
			shardKey = "parent_dbid",
			queryKey = 1,
			updateKey = {1},
			redisKey = function(row)
				return string.format("rdata:%s", row.parent_dbid)
			end,
			updateIndex = 2,
			limit = 1,
			keyMap = {
				parent_dbid = "parentDBID",
				move_speed = "moveSpeed",
				team_level = "teamLevel",
				team_exp = "teamExp",
				fighting_value = "fightingValue",
				school_level = "schoolLevel",
				school_exp = "schoolExp",
				military_lv = "militaryLv",
			},
    	},

		-------------------------------------------------------------------------
		-- role_guild
		-------------------------------------------------------------------------
		role_guild = {
			tableName = "role_guild",
			field = {
				"parent_dbid", "guild_id", "exit_cd", "req_list", "guild_title",
				"last_guild_id",
			},
			dataType = {
				t.number, t.number, t.number, t.table, t.number,
				t.number,
			},
			sharding = 500*10000,
			shardKey = "parent_dbid",
			queryKey = 1,
			updateKey = {1},
			redisKey = function(row)
				return string.format("rguild:%s", row.parent_dbid)
			end,
			updateIndex = 2,
			limit = 1,
			keyMap = {
				parent_dbid = "parentDBID",
				guild_id = "guildID",
				exit_cd = "exitCD",
				req_list = "reqList",
				guild_title = "guildTitle",
				last_guild_id = "lastGuildID",
			},
		},

		-------------------------------------------------------------------------
		-- bag_slots
		-------------------------------------------------------------------------
		bag_slots = {
			tableName = "bag_slots",
			field = {
				"parent_dbid", "item_index", "guid_1", "guid_2", "item_id",
				"count", "data",
			},
			dataType = {
				t.number, t.number, t.number, t.number, t.number,
				t.number, t.table,
			},
			sharding = 30*10000,
			shardKey = "parent_dbid",
			queryKey = 1,
			updateKey = {1, 2},
			redisKey = function(row)
				return string.format("slots:%s:%s", row.parent_dbid, row.item_index)
			end,
			updateIndex = 3,
			limit = 1000,
			--config = "",
			keyMap = {
				parent_dbid = "parentDBID",
				item_index = "index",
				guid_1 = "guid1",
				guid_2 = "guid2",
				item_id = "itemID",
			},
		},

		-------------------------------------------------------------------------
		-- bag
		-------------------------------------------------------------------------
		bag = {
			tableName = "bag",
			field = {
				"parent_dbid", "item_list", 
			},
			dataType = {
				t.number, t.table, 
			},
			sharding = 500*10000,
			shardKey = "parent_dbid",
			queryKey = 1,
			updateKey = {1},
			redisKey = function(row)
				return string.format("bag:%s", row.parent_dbid)
			end,
			updateIndex = 2,
			limit = 1,
			keyMap = {
				parent_dbid = "parentDBID",
				item_list = "itemList",
			},
		},
		
	}
}

-- row_key 前缀 -> 表定义，供 data_sync 落库路由使用
DBDef.redis_prefix_map = {
	["p:"] = DBDef.Table.player.player_data,
	["rbase:"] = DBDef.Table.role.role_base,
	["rdata:"] = DBDef.Table.role.role_data,
	["rguild:"] = DBDef.Table.role.role_guild,
	["slots:"] = DBDef.Table.role.bag_slots,
	["bag:"] = DBDef.Table.role.bag,
}

local function ensure_reverse_key_map(table_def)
	if table_def._reverseKeyMap then
		return
	end
	table_def._reverseKeyMap = {}
	for db_field, logic_field in pairs(table_def.keyMap or {}) do
		table_def._reverseKeyMap[logic_field] = db_field
	end
end

function DBDef.logic_field(table_def, db_field)
	local key_map = table_def.keyMap
	return (key_map and key_map[db_field]) or db_field
end

function DBDef.db_field(table_def, logic_field)
	ensure_reverse_key_map(table_def)
	return table_def._reverseKeyMap[logic_field] or logic_field
end

function DBDef.to_logic_row(table_def, db_row)
	if not db_row then
		return nil
	end
	local row = {}
	for k, v in pairs(db_row) do
		row[DBDef.logic_field(table_def, k)] = v
	end
	return row
end

function DBDef.to_db_row(table_def, logic_row)
	if not logic_row then
		return nil
	end
	local row = {}
	for k, v in pairs(logic_row) do
		row[DBDef.db_field(table_def, k)] = v
	end
	return row
end

function DBDef.logic_fields(table_def)
	if table_def.logicFields then
		return table_def.logicFields
	end
	table_def.logicFields = {}
	for _, db_field in ipairs(table_def.field) do
		table.insert(table_def.logicFields, DBDef.logic_field(table_def, db_field))
	end
	return table_def.logicFields
end

function DBDef.build_redis_key(table_def, row)
	return table_def.redisKey(DBDef.to_db_row(table_def, row))
end

function DBDef.is_multi_row(table_def)
	return (table_def.limit or 1) > 1
end

function DBDef.parse_table_def_by_row_key(row_key)
	for prefix, def in pairs(DBDef.redis_prefix_map) do
		if string.sub(row_key, 1, #prefix) == prefix then
			return def
		end
	end
end

function DBDef.shard_id_base(table_def)
	if table_def.shardKey == "act_id" then
		return DBDef.actBase
	end
	return DBDef.dbidBase
end

function DBDef.calc_table_suffix(table_def, shard_key_value)
	if not table_def.sharding or table_def.sharding <= 0 then
		return DBDef.tableIndexBase
	end
	shard_key_value = tonumber(shard_key_value)
	local id_base = DBDef.shard_id_base(table_def)
	if not shard_key_value or shard_key_value < id_base then
		return DBDef.tableIndexBase
	end
	local shard_idx = math.floor((shard_key_value - id_base) / table_def.sharding)
	return shard_idx + DBDef.tableIndexBase
end

--
--[[
resolve_table_name 接口作用是根据表定义（table_def）、主键或行信息（keys_or_row）、以及可选项 opts，确定并返回实际数据库表名（含分表后缀）。

详细分析：
- opts 参数可以显式指定 table_suffix，如果提供则直接拼接表名返回。
- keys_or_row 允许是完整行或主键映射，如果里头包含分表键（shardKey），则直接使用；否则借助 to_db_row 转成完整行。
- 获取分表键的值，如果没拿到或者为 0，则默认返回基础表（如 table_xxx_1，IndexBase 通常为 1）。
- 其核心逻辑是通过 calc_table_suffix 结合分表 key 值，计算出当前数据应落入的分表后缀号，并拼接实际表名。

用途：
通常用于透明分表场景，使代码能便捷获取正确的物理表名，适应不同业务的分表策略。
]]
function DBDef.resolve_table_name(table_def, keys_or_row, opts)
    opts = opts or {}
    if opts.table_suffix then
        return table_def.tableName .. "_" .. opts.table_suffix
    end
    local db_row
    if keys_or_row then
        if keys_or_row[table_def.shardKey or ""] ~= nil then
            db_row = keys_or_row
        else
            db_row = DBDef.to_db_row(table_def, keys_or_row)
        end
    end
    if not db_row then
        return table_def.tableName .. "_" .. DBDef.tableIndexBase
    end
    local shard_key = table_def.shardKey or table_def.field[table_def.queryKey]
    local shard_val = db_row[shard_key]
    if not shard_val or shard_val == 0 then
        return table_def.tableName .. "_" .. DBDef.tableIndexBase
    end
    return table_def.tableName .. "_" .. DBDef.calc_table_suffix(table_def, shard_val)
end

return DBDef