
/**************************** 
** 账号登录信息
****************************/
DROP TABLE IF EXISTS login_info;

CREATE TABLE login_info (
`act_id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`account` VARCHAR(64) NOT NULL,
`password` VARCHAR(128) NOT NULL,
`register_time` datetime NOT NULL DEFAULT '1970-01-01 00:00:00',
`platform_id` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
`last_server_id` INT UNSIGNED NOT NULL DEFAULT 0,
UNIQUE KEY `un_account` (account(64))
) ENGINE=InnoDB AUTO_INCREMENT=1018168 DEFAULT CHARSET=utf8mb4;


/**************************** 
** 服务器列表
****************************/
DROP TABLE IF EXISTS server_list;

CREATE TABLE server_list (
`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`num` INT UNSIGNED NOT NULL DEFAULT 0,
`name` VARCHAR(32) NOT NULL DEFAULT '',
`group_id` INT UNSIGNED NOT NULL DEFAULT 0,				/* 服务器群id */
`state` TINYINT UNSIGNED NOT NULL DEFAULT 0,			/* 服务器状态：0=维护，1=正常，2=繁忙，3=新服 */
`flag` TINYINT UNSIGNED NOT NULL DEFAULT 0,				/* 服务器标记：0=无，1=推荐 */
`show` TINYINT UNSIGNED NOT NULL DEFAULT 0,             /* 显示标记：0=全不可见，1=内部可见（后台、GM），2=外部可见（客户端），3=创角可见 */
`mark` VARCHAR(32) NOT NULL DEFAULT '',					/* 服务器内部代号,相当于内部使用的服务器名 */
`bi_host` CHAR(32) NOT NULL DEFAULT '',					/* bi数据库的host和数据库名 */
`bi_name` CHAR(32) NOT NULL DEFAULT '',
`game_host` CHAR(32) NOT NULL DEFAULT '',
`game_name` CHAR(32) NOT NULL DEFAULT '',
`global_host` CHAR(32) NOT NULL DEFAULT '',
`global_name` CHAR(32) NOT NULL DEFAULT '',
`paygm_host` CHAR(32) NOT NULL DEFAULT '',
`paygm_name` CHAR(32) NOT NULL DEFAULT ''

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

/**************************** 
 ** 进程状态监控
 ****************************/
DROP TABLE IF EXISTS `server_proc_state`;

CREATE TABLE `server_proc_state` (
`group_id` INT UNSIGNED NOT NULL DEFAULT 0,              /* 服务器组 */
`proc_type` INT UNSIGNED NOT NULL DEFAULT 0,             /* 进程类型 */
`proc_id` INT UNSIGNED NOT NULL DEFAULT 0,               /* 进程ID */
`proc_name` VARCHAR(16) NOT NULL DEFAULT '',             /* 进程名称 */
`state` INT UNSIGNED NOT NULL DEFAULT 0,                 /* 进程状态 */
`update_time` INT UNSIGNED NOT NULL DEFAULT 0,           /* 状态刷新时间 */

PRIMARY KEY (`group_id`,`proc_type`,`proc_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/**************************** 
** 服务端报错
****************************/
DROP TABLE IF EXISTS server_traceback;

CREATE TABLE server_traceback (
`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`group_id` INT UNSIGNED NOT NULL DEFAULT 0,
`hash_key` CHAR(32) NOT NULL,
`traceback_log` TEXT,
`frist_time` DATETIME NOT NULL DEFAULT '1970-01-01 00:00:00',   /* 首次记录时间 */
`last_time` DATETIME NOT NULL DEFAULT '1970-01-01 00:00:00',    /* 最后记录时间 */
`trace_times` INT UNSIGNED NOT NULL DEFAULT 0,
`fixed` TINYINT UNSIGNED NOT NULL DEFAULT 0,

INDEX `idx_group_key` (`group_id`,`hash_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;