-- 该脚本用于校验游戏服数据库（如sk_s1_game）中玩家数据的完整性与一致性，
-- 主要检查数据孤立与关联正确性，适用于多分表、分服结构。
-- 执行方式：mysql -h host -u user -p sk_s1_game < tools/merge_server_verify_game.sql

-- 1. 定义全局数据库名和目标服务器ID，并增大group_concat最大长度，便于后续动态生成SQL语句。
SET @global_db = 'sk_s1_global';
SET @target_sid = 1;
SET SESSION group_concat_max_len = 1000000;

-- 2. 动态拼接所有role_data_N表的parent_dbid，便于后续一并校验。
SELECT GROUP_CONCAT(
  CONCAT('SELECT parent_dbid FROM `', table_name, '`')
  ORDER BY table_name SEPARATOR ' UNION ALL '
) INTO @role_data_union
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name REGEXP '^role_data_[0-9]+$';

-- 3. 获取所有role_base_N表中的dbid，作为全量合法角色数据主键集合。
SELECT GROUP_CONCAT(
  CONCAT('SELECT dbid FROM `', table_name, '`')
  ORDER BY table_name SEPARATOR ' UNION ALL '
) INTO @role_base_union
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name REGEXP '^role_base_[0-9]+$';

-- 4. 获取所有role_guild_N表中parent_dbid与guild_id的映射，以便后续检查角色与公会的关系。
SELECT GROUP_CONCAT(
  CONCAT('SELECT parent_dbid, guild_id FROM `', table_name, '`')
  ORDER BY table_name SEPARATOR ' UNION ALL '
) INTO @role_guild_union
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name REGEXP '^role_guild_[0-9]+$';

-- 5. 汇总所有player_data_N表，便于校验玩家各角色卡槽数据。
SELECT GROUP_CONCAT(
  CONCAT('SELECT act_id, server_id, role_1, role_2, role_3, role_4 FROM `', table_name, '`')
  ORDER BY table_name SEPARATOR ' UNION ALL '
) INTO @player_data_union
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name REGEXP '^player_data_[0-9]+$';

-- 6. 检查孤立的role_data记录：即role_data中的parent_dbid在role_base中找不到对应dbid，意味着有无主的角色数据。
SET @sql = CONCAT(
  'SELECT ''orphan_role_data'' AS check_name, rd.parent_dbid FROM (', @role_data_union,
  ') rd LEFT JOIN (', @role_base_union,
  ') rb ON rd.parent_dbid = rb.dbid WHERE rb.dbid IS NULL LIMIT 20'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 7. 检查player_data各角色卡槽指向不存在的role_base记录（比如部分角色已被删除或脏数据），以发现玩家卡槽的非法引用。
SET @rb_in = CONCAT('(', @role_base_union, ') rb_all');
SET @sql = CONCAT(
  'SELECT ''invalid_player_slot'' AS check_name, pd.act_id, pd.server_id, pd.role_1, pd.role_2, pd.role_3, pd.role_4 FROM (',
  @player_data_union, ') pd WHERE pd.server_id = ', @target_sid,
  ' AND ((pd.role_1 > 0 AND pd.role_1 NOT IN (SELECT dbid FROM ', @rb_in, '))',
  ' OR (pd.role_2 > 0 AND pd.role_2 NOT IN (SELECT dbid FROM ', @rb_in, '))',
  ' OR (pd.role_3 > 0 AND pd.role_3 NOT IN (SELECT dbid FROM ', @rb_in, '))',
  ' OR (pd.role_4 > 0 AND pd.role_4 NOT IN (SELECT dbid FROM ', @rb_in, '))) LIMIT 20'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 8. 检查角色关联的guild_id是否为当前全局服中实际存在的公会。捕捉无效的guild_id引用，避免角色关联了错误/不存在的公会。
SET @sql = CONCAT(
  'SELECT ''invalid_role_guild'' AS check_name, rg.parent_dbid, rg.guild_id FROM (', @role_guild_union,
  ') rg LEFT JOIN `', @global_db, '`.guild_data gd ON rg.guild_id = gd.guild_id',
  ' WHERE rg.guild_id > 0 AND gd.guild_id IS NULL LIMIT 20'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
