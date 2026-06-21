/*
已实现 B+B2 分表，改动如下：

代码

common/db_keys_define.lua — resolve_table_name、calc_table_suffix、shardKey
common/data_access.lua — 4 个 MySQL 入口分表；role_base insert 读 role_table_index；非 _1 表自动 CREATE TABLE LIKE
worldMgr/service/global_data.lua — 维护 role_table_index、定时扩容、ensure_bag_shards
data/game/migrate_shard.sql — 改为 *_1
data/game/game_shard.sql — 新建初始分表
部署

已有库：game 库跑 game.sql + migrate_shard.sql；global 库跑 data/global/global.sql
新库：game 库跑 game_shard.sql；global 库跑 data/global/global.sql
确认 sk_s{N}_global.game_global.role_table_index 初始为 1
*/

RENAME TABLE `player_data` TO `player_data_1`;
RENAME TABLE `role_base` TO `role_base_1`;
RENAME TABLE `role_data` TO `role_data_1`;
RENAME TABLE `bag_slots` TO `bag_slots_1`;
RENAME TABLE `role_guild` TO `role_guild_1`;
