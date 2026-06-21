-- 脚本作用分析
-- 该 SQL 脚本用于在合服全局库（如 sk_s1_global）中，
--对合服过程中的相关表进行数据校验和统计，以辅助排查或验证合服数据一致性。
--执行方式：mysql -h host -u user -p sk_s1_global < tools/merge_server_verify_global.sql

-- 1. 变量初始化
-- 设置目标游戏数据库名和 group_concat 的长度，便于接下来的动态 SQL 拼接。
SET @game_db = 'sk_s1_game';
SET SESSION group_concat_max_len = 1000000;

-- 2. 生成所有 role_base_xxx 表的联合查询，用于后续比对
-- 动态拼接所有 role_base_数字 表（即分表）的 dbid 字段，并生成 UNION ALL 查询，
-- 合并所有玩家角色ID，便于后续校验是否有公会成员（guild_member）所关联的角色实际不存在于角色表中。
SELECT GROUP_CONCAT(
  CONCAT('SELECT dbid FROM `', @game_db, '`.`', table_name, '`')
  ORDER BY table_name SEPARATOR ' UNION ALL '
) INTO @role_base_union
FROM information_schema.tables
WHERE table_schema = @game_db AND table_name REGEXP '^role_base_[0-9]+$';

-- 3. 检查孤立的公会成员
-- 动态执行上述生成的 SQL，查找 guild_member 表中 role_dbid 没有对应角色数据的异常条目（即外键不存在的“孤儿”记录），最多查出 20 条。
SET @sql = CONCAT(
  'SELECT ''orphan_guild_member'' AS check_name, gm.role_dbid, gm.guild_id FROM guild_member gm LEFT JOIN (',
  @role_base_union, ') rb ON gm.role_dbid = rb.dbid WHERE gm.role_dbid > 0 AND rb.dbid IS NULL LIMIT 20'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 4. 检查合服全局表关键配置
-- 查询 game_global 表（idx = 1）中的 role 表分表索引号与服务器启动时间，作为全局配置核查。
SELECT 'game_global' AS check_name, role_table_index, server_start_time
FROM game_global WHERE idx = 1;

-- 5. 检查溢出玩家数据
-- 统计 merge_overflow_roles 表中溢出角色的数量，此表一般用于记录因主键冲突等原因暂时存放的溢出数据。
SELECT 'overflow_roles' AS check_name, COUNT(*) AS cnt FROM merge_overflow_roles;

-- 6. 检查 ID 映射情况
-- 按 id_type 分组统计合服过程中的 ID 映射数量，用于确认各种合服 ID 的转换情况。
SELECT 'id_map' AS check_name, id_type, COUNT(*) AS cnt
FROM merge_id_map
GROUP BY id_type;

-- 7. 检查重命名日志
-- 按 entity_type 分组统计合服中因重名而记录的重命名日志数目。
SELECT 'rename_log' AS check_name, entity_type, COUNT(*) AS cnt
FROM merge_rename_log
GROUP BY entity_type;
