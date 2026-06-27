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
 ** 不占格背包
 ****************************/
DROP TABLE IF EXISTS `bag`;

CREATE TABLE `bag` (
`parent_dbid` INT UNSIGNED NOT NULL PRIMARY KEY,
`item_list` TEXT
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


/**************************** 
 ** 任务数据
 ****************************/
DROP TABLE IF EXISTS `task`;

CREATE TABLE `task` (
`parent_dbid` INT UNSIGNED NOT NULL,						
`task_index` INT UNSIGNED NOT NULL DEFAULT 0,			/* 任务数据序号 */
`task_id` INT UNSIGNED NOT NULL,							/* 任务id */
`data` TEXT, 												/* 任务数据 */
`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,				/* 任务状态 */
`time` INT UNSIGNED NOT NULL DEFAULT 0,                     /* 接任务时间 */

PRIMARY KEY (`parent_dbid`, `task_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 侠客列表
 ****************************/
DROP TABLE IF EXISTS `partner_list`;

CREATE TABLE `partner_list` (
`parent_dbid` INT UNSIGNED NOT NULL DEFAULT 0,              /* 玩家dbid */
`partner_index` SMALLINT UNSIGNED NOT NULL DEFAULT 0,       /* 伙伴格子索引 */
`partner_id` INT UNSIGNED NOT NULL DEFAULT 0,               /* 伙伴id */
`level` SMALLINT UNSIGNED NOT NULL DEFAULT 0,               /* 等级 */
`grade` INT UNSIGNED NOT NULL DEFAULT 0,                    /* 品阶 */
`maxhp` BIGINT UNSIGNED NOT NULL DEFAULT 0,                 /* 生命 */
`speed` INT UNSIGNED NOT NULL DEFAULT 0,                    /* 速度 */
`attack` INT UNSIGNED NOT NULL DEFAULT 0,                   /* 攻击 */
`defense` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 防御 */
`crit` INT UNSIGNED NOT NULL DEFAULT 0,                     /* 暴击 */
`de_crit` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 抗暴 */
`crit_dam` INT UNSIGNED NOT NULL DEFAULT 0,                 /* 暴伤 */
`de_crit_dam` INT UNSIGNED NOT NULL DEFAULT 0,              /* 韧性 */
`acc` INT UNSIGNED NOT NULL DEFAULT 0,                      /* 命中 */
`miss` INT UNSIGNED NOT NULL DEFAULT 0,                     /* 闪避 */
`incr_dam` INT UNSIGNED NOT NULL DEFAULT 0,                 /* 增伤 */
`decr_dam` INT UNSIGNED NOT NULL DEFAULT 0,                 /* 免伤 */
`cure` INT UNSIGNED NOT NULL DEFAULT 0,                     /* 治疗 */
`be_cured` INT UNSIGNED NOT NULL DEFAULT 0,                 /* 受疗 */
`control` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 控制 */
`de_control` INT UNSIGNED NOT NULL DEFAULT 0,               /* 扛控 */
`phy_dam` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 物伤 */
`de_phy_dam` INT UNSIGNED NOT NULL DEFAULT 0,               /* 物免 */
`eng_dam` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 高伤 */
`de_eng_dam` INT UNSIGNED NOT NULL DEFAULT 0,               /* 高免 */
`cure_crit` INT UNSIGNED NOT NULL DEFAULT 0,                /* 治疗暴击 */
`fv` INT UNSIGNED NOT NULL DEFAULT 0,                       /* 战斗力 */
`ext_buff` TEXT,                                            /* 扩展buff列表 */
`lock` TINYINT UNSIGNED NOT NULL DEFAULT 0,                 /* 锁状态 */
`skill_list` TEXT,                                          /* 技能列表 */
`chips` TEXT,                                               /* 芯片 */
`weapon1` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 装备 */
`weapon2` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 装备 */
`weapon3` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 装备 */
`weapon4` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 装备 */

PRIMARY KEY (`parent_dbid`, `partner_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


