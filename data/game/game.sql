DROP TABLE IF EXISTS `player_data`;

CREATE TABLE `player_data` (
`act_id` INT UNSIGNED NOT NULL ,                            /* 账号id */
`server_id` INT UNSIGNED NOT NULL DEFAULT 0,                /* 服务器ID */
`online` TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,			/* 是否在线 */
`online_time` INT UNSIGNED NOT NULL DEFAULT 0,				/* 累计在线时长 */
`select_role` INT UNSIGNED NOT NULL DEFAULT 0,				/* 当前选择角色的dbid */
`role_1` INT UNSIGNED NOT NULL DEFAULT 0,					/* 角色1 */
`role_2` INT UNSIGNED NOT NULL DEFAULT 0,					/* 角色2 */
`role_3` INT UNSIGNED NOT NULL DEFAULT 0,					/* 角色3 */
`role_4` INT UNSIGNED NOT NULL DEFAULT 0,					/* 角色4 */
`shutup` INT UNSIGNED NOT NULL DEFAULT 0,					/* 禁言 */
`create_time` INT UNSIGNED NOT NULL DEFAULT 0,              /* 建号时间 */

PRIMARY KEY (`act_id`, `server_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;



/**************************** 
 ** 角色基础数据(固定数据)
 ****************************/
DROP TABLE IF EXISTS `role_base`;

CREATE TABLE `role_base` (
`dbid` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,	/* 角色dbid */
`act_id` INT UNSIGNED NOT NULL,								/* 账号id */
`server_id` INT UNSIGNED NOT NULL DEFAULT 0,                /* 服务器ID */
`name` VARCHAR(32) NOT NULL,								/* 角色姓名 */
`create_time` INT UNSIGNED NOT NULL DEFAULT 0,              /* 角色创建时间 */
`sex` TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,				/* 角色性别 */

KEY `key_act_id` (`act_id`),
KEY `key_name` (`name`(32))
) ENGINE=InnoDB AUTO_INCREMENT=10518 DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 角色数据（角色属性相关数据）
 ****************************/
DROP TABLE IF EXISTS `role_data`;

CREATE TABLE `role_data` (
`parent_dbid` INT UNSIGNED NOT NULL PRIMARY KEY,            /* 角色dbid */
`move_speed` INT UNSIGNED NOT NULL DEFAULT 0,               /* 移动速度 */
`team_level` INT UNSIGNED NOT NULL DEFAULT 0,               /* 队伍等级 */
`team_exp` INT UNSIGNED NOT NULL DEFAULT 0,                 /* 队伍经验 */
`fighting_value` INT UNSIGNED NOT NULL DEFAULT 0,           /* 总战斗力 */
`school_level` INT UNSIGNED NOT NULL DEFAULT 0,				/* 流派等级 */
`school_exp` INT UNSIGNED NOT NULL DEFAULT 0,               /* 流派经验 */
`military_lv` INT UNSIGNED NOT NULL DEFAULT 0				/* 军衔等级 */

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 背包格子
 ****************************/
DROP TABLE IF EXISTS `bag_slots`;

CREATE TABLE `bag_slots` (
`parent_dbid` INT UNSIGNED NOT NULL DEFAULT 0,              /* 玩家dbid */
`item_index` SMALLINT UNSIGNED NOT NULL DEFAULT 0,          /* 背包格子索引 */
`guid_1` INT UNSIGNED NOT NULL DEFAULT 0,                   /* 物品全局标识1 */
`guid_2` INT UNSIGNED NOT NULL DEFAULT 0,                   /* 物品全局标识2 */
`item_id` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 物品id */
`count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,               /* 物品数量 */
`data` TEXT,                                                /* 物品数据 */

PRIMARY KEY (`parent_dbid`, `item_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 联盟个人数据
 ****************************/
DROP TABLE IF EXISTS `role_guild`;
CREATE TABLE `role_guild` (
`parent_dbid` INT UNSIGNED NOT NULL PRIMARY KEY, 	/*玩家dbid*/
`guild_id` INT UNSIGNED NOT NULL DEFAULT 0,			/* 联盟ID */
`exit_cd` INT UNSIGNED NOT NULL DEFAULT 0,			/* 冷却时间 */
`req_list` TEXT, 									/* 申请列表 */
`guild_title` TINYINT UNSIGNED NOT NULL DEFAULT 0, /* 联盟头衔 */
`last_guild_id` INT UNSIGNED NOT NULL DEFAULT 0	/* 上一次加入的联盟ID */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;