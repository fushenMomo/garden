# garden
garden是一套基于skynet框架的多进程服务器框架。


基于 Skynet 的多进程游戏服务端，目录如下：

## 根目录脚本
- `start.sh` / `stop.sh` — 启停全部游戏进程
- `start_console.sh` / `stop_console.sh` / `check_console.sh` / `check.sh` — 控制台与进程检查

## skynet/
Skynet 框架本体（C 核心、lualib、内置 service、第三方库 lua/jemalloc 等）。业务代码在上层目录，此处一般不改动。

## 业务进程（各含 `*_main.lua` 入口 + `service/` 子服务）

| 目录 | 职责 |
|------|------|
| `login/` | 账号登录、服务器列表、TCP 8888 |
| `gateway/` | 客户端网关，转发 sproto 协议 |
| `world/` | 游戏逻辑：玩家/背包/好友/邮件/任务/公会等 agent，以及 guild 独立服务 |
| `worldMgr/` | 单服全局数据管理（跨 world 进程） |
| `serverMgr/` | 全局管理,跨服功能支持 |
| `webAPI/` | HTTP 8900，GM/运营接口（player/guild/system） |
| `console/` | 调试控制台进程 |

进程拓扑与端口由 `etc/topology.yaml` 定义，当前配置 2 个 server group，每组 2 gateway + 2 world。

## common/
各进程共享库：
- 数据层：`data_access.lua`、`db_keys_define.lua`、`mysqlpool.lua`、`redispool.lua`、`row_cache.lua`、`data_sync.lua`、`cache_evict.lua`
- 通信：`ms_rpc.lua`、`svc_registry.lua`、`proto.lua`、`protoloader.lua`
- 工具：`logger.lua`、`util.lua`、`config_mgr.lua`、`const.lua` 等

## sproto/
客户端协议定义：`c2s.sproto`（客户端→服务端）、`s2c.sproto`（服务端→客户端）。

## config/
静态策划配置表，如 `cfg_item.lua`。

## data/
MySQL 建表脚本：
- `login/login.sql` — 账号、服务器列表
- `game/game.sql` — 玩家/角色等个人数据
- `game/game_shard.sql`、`migrate_shard.sql` — 分表方案
- `global/global.sql` — 全服全局数据、pending_job 等
- `global/merge_server.sql` — 合服相关表结构

库名格式：`sk_s{server_id}_game`、`sk_s{server_id}_global`。

## etc/
运行时配置：
- `config.*` — 各进程 Skynet 配置（DB/Redis/端口等）
- `clustername.*` — 集群节点名

## tools/
运维工具：
- `merge_server.py` — 合服脚本
- `merge_server_verify_*.sql` — 合服校验
- `requirements-merge.txt` — Python 依赖

## .cursor/plans/
设计文档（合服、分表、缓存框架等），非运行时代码。
