
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