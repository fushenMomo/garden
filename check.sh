#!/bin/bash

TAG=(
    skynet_serverMgr
    skynet_login
    skynet_webAPI
    skynet_worldMgr_1_1
    skynet_bi_1_1
    skynet_world_1_1
    skynet_world_1_2
    skynet_gateway_1_1
    skynet_gateway_1_2
    skynet_worldMgr_2_1
    skynet_bi_2_1
    skynet_world_2_1
    skynet_world_2_2
    skynet_gateway_2_1
    skynet_gateway_2_2
    skynet_worldMgr_3_1
    skynet_bi_3_1
    skynet_world_3_1
    skynet_world_3_2
    skynet_gateway_3_1
    skynet_gateway_3_2
)
HAS_RUNNING=0

for tag in "${TAG[@]}"; do
    running=$(pgrep -af "$tag")
    if [ -n "$running" ]; then
        echo "---------- $tag ----------"
        echo "$running"
        HAS_RUNNING=1
    fi
done

if [ "$HAS_RUNNING" -eq 1 ]; then
    exit 0
else
    exit 1
fi
