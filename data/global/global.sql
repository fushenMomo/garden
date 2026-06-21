
/***********************************************
 ** game_global:一些全局的服务器配置数据
 ************************************************/
DROP TABLE IF EXISTS game_global;

CREATE TABLE game_global (
`idx` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`last_0am_update` INT UNSIGNED NOT NULL DEFAULT 0,	/* 最后一次凌晨0点更新时间 */
`last_6am_update` INT UNSIGNED NOT NULL DEFAULT 0,	/* 最后一次凌晨6点更新时间 */
`server_start_time` INT UNSIGNED NOT NULL DEFAULT 0, 	/* 服务器首次开启时间 */
`role_table_index` TINYINT UNSIGNED NOT NULL DEFAULT 0	/* 角色表的分表最大索引 */

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 待处理事务
 ****************************/
DROP TABLE IF EXISTS `pending_job`;
CREATE TABLE `pending_job` (
`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`parent_dbid` INT UNSIGNED NOT NULL,						/* 角色dbid */
`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,				/* 事务状态 */
`create_time` INT UNSIGNED NOT NULL DEFAULT 0,				/* 事务创建时间 */
`finish_time` INT UNSIGNED NOT NULL DEFAULT 0,				/* 事务完成时间 */
`job_data` TEXT,											/* 事务数据 */

KEY `key_parent_dbid` (`parent_dbid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 待处理事务处理完成记录
 ****************************/
DROP TABLE IF EXISTS `pending_job_log`;
CREATE TABLE `pending_job_log` (
`id` INT UNSIGNED NOT NULL,
`parent_dbid` INT UNSIGNED NOT NULL,						/* 角色dbid */
`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,				/* 事务状态 */
`create_time` INT UNSIGNED NOT NULL DEFAULT 0,				/* 事务创建时间 */
`finish_time` INT UNSIGNED NOT NULL DEFAULT 0,				/* 事务完成时间 */
`job_data` TEXT,											/* 事务数据 */

INDEX `idx_id` (`id`),
KEY `key_parent_dbid` (`parent_dbid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 公会成员
 ****************************/
DROP TABLE IF EXISTS guild_member;
CREATE TABLE guild_member (
`guild_id` INT UNSIGNED NOT NULL,                 /* 公会id */
`index` INT UNSIGNED NOT NULL,                 	  /* 成员索引（保存数据需要） */
`role_dbid` INT UNSIGNED NOT NULL DEFAULT 0,      /* 角色dbid */
`sex` TINYINT UNSIGNED NOT NULL DEFAULT 0,        /* 成员性别 */
`standing` TINYINT UNSIGNED NOT NULL DEFAULT 0,   /* 地位 */
`name` VARCHAR(16) NOT NULL DEFAULT '',           /* 角色姓名 */
`fighting_value` INT UNSIGNED NOT NULL DEFAULT 0, /* 战斗力 */
`logout_time` INT UNSIGNED NOT NULL DEFAULT 0,    /* 下线时间 */
`join_time` INT UNSIGNED NOT NULL DEFAULT 0,      /* 加入时间 */

PRIMARY KEY (`guild_id`, `index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
 ** 公会
 ****************************/
DROP TABLE IF EXISTS guild_data;
CREATE TABLE guild_data (
`guild_id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,/* 公会id */
`name` VARCHAR(20) NOT NULL,                              /* 公会名 */
`brief` VARCHAR(150) NOT NULL DEFAULT "",                 /* 公会宣言 */
`head_id` INT UNSIGNED NOT NULL DEFAULT 0,                /* 头像 */
`member_count` INT UNSIGNED NOT NULL DEFAULT 0,           /* 人数 */
`level` INT UNSIGNED NOT NULL DEFAULT 0,                  /* 公会等级 */
`exp` INT UNSIGNED NOT NULL DEFAULT 0,                    /* 公会经验 */
`create_time` INT UNSIGNED NOT NULL DEFAULT 0,            /* 公会创建时间 */
`approval_status` INT UNSIGNED NOT NULL DEFAULT 0,        /* 审批状态 */
`req_list` TEXT,                                          /* 申请加入信息 */
`rename_times` INT UNSIGNED NOT NULL DEFAULT 0,           /* 公会改名次数 */
KEY `key_name` (`name`(20))
) ENGINE=InnoDB AUTO_INCREMENT=1018 DEFAULT CHARSET=utf8mb4;