#!/bin/bash

TAG="skynet_console"
PIDS=$(pgrep -f "$TAG")

if [ -z "$PIDS" ]; then
    echo "console is not running."
    exit 0
fi

echo "stopping console, pids: $PIDS"
kill $PIDS
sleep 1

if pgrep -f "$TAG" >/dev/null; then
    echo "console still running, you can force stop with:"
    echo "kill -9 \$(pgrep -f \"$TAG\")"
    exit 1
else
    echo "console stopped."
    exit 0
fi
