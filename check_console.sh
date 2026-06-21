#!/bin/bash

TAG="skynet_console"

if pgrep -af "$TAG" >/dev/null; then
    echo "console is running:"
    pgrep -af "$TAG"
    exit 0
else
    echo "console is not running."
    exit 1
fi

