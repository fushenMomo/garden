local const = {}

const.login_type = {
    default = 0,
    wx = 1, --微信
    dy = 2, --抖音
    ks = 3, --快手
    max = 3,
}

const.error_code = {
    success = 0,
    invalid_params = 1, -- 参数错误

    -- 登录相关功能
    name_or_pass_too_long = 1001, -- 名字或者密码太长
    user_exists = 1002,    -- 用户已经存在
    unknown_user = 1003,   -- 不存在的用户
    bad_password = 1004,   -- 密码错误
    bad_token = 1005,
    expired = 1006,
    platform_error = 1007, -- 平台参数错误
    insert_account_failed = 1008, -- 新建帐号失败

    -- 选择服务器相关功能
    server_not_found = 2001, -- 服务器不存在

    -- 登录游戏服
    join_game_time_out = 3001, -- 登录游戏服超时
    join_game_world_failed = 3002, -- 登录游戏服失败
    not_in_game = 3003, -- 尚未进入游戏
    unknown_proto = 3004, -- 未知协议
    world_request_failed = 3005, -- 转发到 world 失败

    -- role相关功能
    role_name_too_long = 4001, -- 角色昵称太长

    -- 公会相关功能
    invalid_guild_name = 5001, -- 公会名称无效
    invalid_guild_brief = 5002, -- 公会宣言无效
    create_guild_failed = 5003, -- 创建公会失败
    already_in_guild = 5004, -- 已经加入公会
    join_guild_failed = 5005, -- 加入公会失败
    invalid_guild_id = 5006, -- 公会ID无效
    not_in_guild = 5007, -- 尚未加入公会
    change_guild_desc_failed = 5008, -- 修改公会描述失败
    not_guild_ownner = 5009, -- 不是公会会长

    -- 背包相关功能
    item_not_found = 6001, -- 物品不存在
    add_item_failed = 6002, -- 添加物品失败
    sub_item_failed = 6003, -- 扣除物品失败

    -- 伙伴相关功能
    partner_not_found = 7001, -- 伙伴不存在
    add_partner_failed = 7002, -- 添加伙伴失败

    -- 任务相关功能
    task_not_found = 8001, -- 任务不存在
    task_not_completed = 8002, -- 任务未完成
    task_reward_received = 8003, -- 任务奖励已领取
    add_task_failed = 8004, -- 添加任务失败

    -- 战斗相关功能
    start_fight_failed = 9001, -- 发起战斗失败
    end_fight_failed = 9002, -- 结束战斗失败
}

const.cache_ttl = {
    timeout = 604800, -- 离线行缓存 TTL（秒），默认 7 天
}

const.cache_evict = {
    scan_interval_hours = 6, -- 扫描间隔（小时）
    idle_hours = 1,         -- 超过该小时数未登录则清除行缓存（默认 3 天）
    batch_size = 1000,        -- 每批处理玩家数，批间让出 CPU
}

const.redis_key = {
    -- 行缓存（与 db_keys_define.redisKey 格式一致）
    player_data = "p:%s:%s",        -- server_id, act_id
    --role_base = "rbase:%s",         -- dbid
    --role_data = "rdata:%s",         -- parent_dbid
    --bag_slots = "slots:%s:%s",      -- parent_dbid, item_index

    -- 脏数据落库
    dirty_queue = "dirty:queue",    -- list lpush,lpop
    dirty_fields = "dirty:fields:%s", -- row_key smembers dirty_fields

    -- 在线索引
    online = "online:%s:%s",        -- server_id, act_id
    world_role = "world_role:%s:%s", -- server_id, dbid

    -- 玩家最后登录时间（有序集合，score=时间戳，member=act_id）
    last_login = "last_login:%s",   -- server_id

    -- 落库分布式锁
    flush_lock = "flush:lock:%s",   -- row_key

    -- 定时器（按 server_id + proc_id 隔离，每个 world 进程独立队列）
    timer_queue = "timer:queue:%s:%s",  -- server_id, proc_id
    timer_data = "timer:data:%s:%s",    -- server_id, proc_id

    bi_queue = "bi:queue:%s",           -- server_id
}

const.timer = {
    poll_interval = 100,   -- 轮询间隔（skynet 百分之一秒），默认 1s
    recover_batch = 100,   -- 启动恢复时每批处理数量
}

const.sex = {
    boy = 0,
    girl = 1,
}

-- 背包格子相关常量
const.bag_slots = {
    default_count = 10, -- 背包格子默认数量
    max_count = 100, -- 背包格子最大数量
}

const.task = {
    max_count = 500, -- 任务最大数量
}

const.task_status = {
    going = 1, -- 进行中
    completed = 2, -- 已经完成
    received = 3, -- 已经领取奖励
}

const.task_accept_type = {
    login = 1,
    rename = 2,
}

const.task_complete_type = {
    partner_count = 1,
}

-- world_agent的业务功能模块
const.world_agent_module = {
    player = "player", -- 玩家数据
    bag = "bag", -- 背包数据
    task = "task", -- 任务数据
    mail = "mail", -- 邮件数据
    friend = "friend", -- 好友数据
    guild = "guild", -- 公会数据
    partner = "partner", -- 伙伴数据
    fight = "fight", -- 战斗数据
}

const.world_agent_module_sort = {
    player = 1,
    bag = 2,
    task = 3,
    mail = 4,
    friend = 5,
    guild = 6,
    partner = 7,
    fight = 8,
}
const.partner = {
    max_count = 200, --伙伴最大数量
}

const.item_type = {	-- 物品类型
    -- 可以有很多种 ->->
    prop = 1, 	-- 道具
    box = 2,  	-- 宝箱
    equip = 3, 	-- 套装
    other = 4,  -- 其他
    weapon = 5, -- 装备
    chip = 6,   -- 芯片
    partner = 7, -- 特工
}

const.heartbeat_timeout = 90 -- 心跳超时时间，90秒

const.guild_standing = {
    member = 0, -- 成员
    ownner = 1, -- 会长
}

const.proc_type = {
    login = 1,
    gateway = 2,
    world = 3,
    worldMgr = 4,
    serverMgr = 5,
    bi = 6,
    webAPI = 7,
}

const.proc_state = {
    init = 0,
    running = 1,
    closed = 2,
}

-- 进程状态监控相关配置
const.proc_state_monitor = {
    heartbeat_interval = 3000,  -- 心跳包间隔时间，单位：毫秒
    stale_timeout = 90,         -- 状态过期时间，单位：秒
    scan_interval = 6000,       -- 状态扫描间隔，单位：毫秒
}


const.fight_type = {
    challenge = 1, -- 普通战斗

}

return const