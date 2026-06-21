#!/bin/bash

TAG=(
    skynet_webAPI
    skynet_gateway_1_2
    skynet_gateway_1_1
    skynet_world_1_2
    skynet_world_1_1
    skynet_worldMgr_1_1
    skynet_gateway_2_2
    skynet_gateway_2_1
    skynet_world_2_2
    skynet_world_2_1
    skynet_worldMgr_2_1
    skynet_login
    skynet_serverMgr_1_1
)
HAS_RUNNING=0
STOP_FAILED=0

for tag in "${TAG[@]}"; do
    pids=$(pgrep -f "$tag")

    if [ -z "$pids" ]; then
        echo "$tag is not running."
        continue
    fi

    HAS_RUNNING=1
    echo "stopping $tag, pids: $pids"
    kill $pids
done

if [ "$HAS_RUNNING" -eq 0 ]; then
    exit 0
fi

sleep 1

for tag in "${TAG[@]}"; do
    if pgrep -f "$tag" >/dev/null; then
        echo "$tag still running, you can force stop with:"
        echo "kill -9 \$(pgrep -f \"$tag\")"
        STOP_FAILED=1
    else
        echo "$tag stopped."
    fi
done

if [ "$STOP_FAILED" -eq 1 ]; then
    exit 1
else
    exit 0
fi
