#!/bin/bash

GRACEFUL_TIMEOUT=30

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

graceful_stop_one() {
    local tag=$1
    local pidfile=$2
    local pid
    pid=$(get_pid "$tag" "$pidfile") || {
        echo "$tag is not running."
        return 0
    }

    echo "graceful stopping $tag (pid=$pid) ..."
    kill -USR1 "$pid" 2>/dev/null || true
    local i=0
    while [ "$i" -lt "$GRACEFUL_TIMEOUT" ]; do
        kill -0 "$pid" 2>/dev/null || {
            echo "$tag stopped."
            return 0
        }
        sleep 1
        i=$((i + 1))
    done

    echo "force stopping $tag ..."
    kill "$pid" 2>/dev/null || true
}

force_stop_one() {
    local tag=$1
    local pidfile=$2
    local pid
    pid=$(get_pid "$tag" "$pidfile") || return 0
    kill -9 "$pid" 2>/dev/null || true
}

GATEWAY_LIST=(
    "skynet_gateway_1_1:log/gateway/gateway_1_1.pid"
    "skynet_gateway_1_2:log/gateway/gateway_1_2.pid"
    "skynet_gateway_2_1:log/gateway/gateway_2_1.pid"
    "skynet_gateway_2_2:log/gateway/gateway_2_2.pid"
    "skynet_gateway_3_1:log/gateway/gateway_3_1.pid"
    "skynet_gateway_3_2:log/gateway/gateway_3_2.pid"
)

WORLD_LIST=(
    "skynet_world_1_1:log/world/world_1_1.pid"
    "skynet_world_1_2:log/world/world_1_2.pid"
    "skynet_world_2_1:log/world/world_2_1.pid"
    "skynet_world_2_2:log/world/world_2_2.pid"
    "skynet_world_3_1:log/world/world_3_1.pid"
    "skynet_world_3_2:log/world/world_3_2.pid"
)

WORLDMGR_LIST=(
    "skynet_worldMgr_1_1:log/worldMgr/worldMgr_1_1.pid"
    "skynet_worldMgr_2_1:log/worldMgr/worldMgr_2_1.pid"
    "skynet_worldMgr_3_1:log/worldMgr/worldMgr_3_1.pid"
)

OTHER_LIST=(
    "skynet_bi_1_1:log/bi/bi_1_1.pid"
    "skynet_bi_2_1:log/bi/bi_2_1.pid"
    "skynet_bi_3_1:log/bi/bi_3_1.pid"
    "skynet_webAPI:log/webAPI/webAPI.pid"
    "skynet_serverMgr:log/serverMgr/serverMgr.pid"
    "skynet_login:log/login/login.pid"
)

HAS_RUNNING=0
STOP_FAILED=0

for item in "${GATEWAY_LIST[@]}" "${WORLD_LIST[@]}" "${WORLDMGR_LIST[@]}" "${OTHER_LIST[@]}"; do
    tag=${item%%:*}
    if pgrep -f "$tag" >/dev/null 2>&1; then
        HAS_RUNNING=1
        break
    fi
done

if [ "$HAS_RUNNING" -eq 0 ]; then
    echo "no skynet process running."
    exit 0
fi

for item in "${GATEWAY_LIST[@]}"; do
    graceful_stop_one "${item%%:*}" "${item#*:}"
done

for item in "${WORLD_LIST[@]}"; do
    graceful_stop_one "${item%%:*}" "${item#*:}"
done

sleep 1

for item in "${WORLDMGR_LIST[@]}"; do
    graceful_stop_one "${item%%:*}" "${item#*:}"
done

for item in "${OTHER_LIST[@]}"; do
    graceful_stop_one "${item%%:*}" "${item#*:}"
done

sleep 1

ALL_LIST=("${GATEWAY_LIST[@]}" "${WORLD_LIST[@]}" "${WORLDMGR_LIST[@]}" "${OTHER_LIST[@]}")
for item in "${ALL_LIST[@]}"; do
    tag=${item%%:*}
    pidfile=${item#*:}
    pid=$(get_pid "$tag" "$pidfile" 2>/dev/null) || continue
    if kill -0 "$pid" 2>/dev/null; then
        echo "$tag still running, force kill ..."
        force_stop_one "$tag" "$pidfile"
        STOP_FAILED=1
    fi
done

for item in "${ALL_LIST[@]}"; do
    tag=${item%%:*}
    if pgrep -f "$tag" >/dev/null; then
        echo "$tag still running after force kill."
        STOP_FAILED=1
    else
        echo "$tag stopped."
    fi
done

if [ "$STOP_FAILED" -eq 1 ]; then
    exit 1
fi
exit 0
