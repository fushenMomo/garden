#!/bin/bash

flush() {
	echo "flush all ${1} ${2}"
	/usr/local/bin/redis-cli -h $1 -p $2 -a "r12345" flushall
}

port_list="8000 8001 8002 8003"

#port_list="8000 6379"

for s in $port_list
do
  flush "127.0.0.1" "${s}"
done

