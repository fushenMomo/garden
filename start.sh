#!/bin/bash

cd ./skynet

SERVICES=(
    serverMgr
    login
    webAPI
    gateway_1_1
    gateway_1_2
    worldMgr_1_1
    bi_1_1
    world_1_1
    world_1_2
    gateway_2_1
    gateway_2_2
    worldMgr_2_1
    bi_2_1
    world_2_1
    world_2_2
    gateway_3_1
    gateway_3_2
    worldMgr_3_1
    bi_3_1
    world_3_1
    world_3_2
)

for name in "${SERVICES[@]}"; do
    bash -c "exec -a skynet_${name} ./skynet ../etc/config.${name}"
    echo "start ${name} ..."
    sleep 2
done
