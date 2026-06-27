#!/bin/bash

get_pid() {
    local tag=$1
    local pidfile=$2
    local pid=""
    if [ -n "$pidfile" ] && [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile" 2>/dev/null)
    fi
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        return 0
    fi
    pid=$(pgrep -f "$tag" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi
    return 1
}
kill_one() {
    local tag=$1
    local pidfile=$2
    local pid
    pid=$(get_pid "$tag" "$pidfile") || {
        echo "$tag is not running."
        return 0
    }
    echo "kill -9 $tag (pid=$pid) ..."
    kill -9 "$pid" 2>/dev/null || true
}

ALL_LIST=(
    "skynet_gateway_1_1:log/gateway/gateway_1_1.pid"
    "skynet_gateway_1_2:log/gateway/gateway_1_2.pid"
    "skynet_gateway_2_1:log/gateway/gateway_2_1.pid"
    "skynet_gateway_2_2:log/gateway/gateway_2_2.pid"
    "skynet_gateway_3_1:log/gateway/gateway_3_1.pid"
    "skynet_gateway_3_2:log/gateway/gateway_3_2.pid"
    "skynet_world_1_1:log/world/world_1_1.pid"
    "skynet_world_1_2:log/world/world_1_2.pid"
    "skynet_world_2_1:log/world/world_2_1.pid"
    "skynet_world_2_2:log/world/world_2_2.pid"
    "skynet_world_3_1:log/world/world_3_1.pid"
    "skynet_world_3_2:log/world/world_3_2.pid"
    "skynet_worldMgr_1_1:log/worldMgr/worldMgr_1_1.pid"
    "skynet_worldMgr_2_1:log/worldMgr/worldMgr_2_1.pid"
    "skynet_worldMgr_3_1:log/worldMgr/worldMgr_3_1.pid"
    "skynet_serverMgr:log/serverMgr/serverMgr.pid"
    "skynet_login_1:log/login/login_1.pid"
    "skynet_login_2:log/login/login_2.pid"
    "skynet_webAPI:log/webAPI/webAPI.pid"
    "skynet_bi_1_1:log/bi/bi_1_1.pid"
    "skynet_bi_2_1:log/bi/bi_2_1.pid"
    "skynet_bi_3_1:log/bi/bi_3_1.pid"
)

for item in "${ALL_LIST[@]}"; do
    kill_one "${item%%:*}" "${item#*:}"
done

for pid in $(pgrep -f "skynet_" 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
done

for item in "${ALL_LIST[@]}"; do
    tag=${item%%:*}
    if pgrep -f "$tag" >/dev/null 2>&1; then
        echo "$tag still running."
        exit 1
    fi
done

echo "all skynet processes killed."
exit 0
