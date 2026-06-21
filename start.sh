#!/bin/bash

cd ./skynet

SERVICES=(
    serverMgr_1_1
    login
    webAPI
    gateway_1_1
    gateway_1_2
    worldMgr_1_1
    world_1_1
    world_1_2
    gateway_2_1
    gateway_2_2
    worldMgr_2_1
    world_2_1
    world_2_2
)

for name in "${SERVICES[@]}"; do
    bash -c "exec -a skynet_${name} ./skynet ../etc/config.${name}"
    echo "start ${name} ..."
    sleep 2
done
