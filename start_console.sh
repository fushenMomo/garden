#!/bin/bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/skynet" || exit 1

if [ -t 0 ] && command -v rlwrap >/dev/null 2>&1; then
  exec "$ROOT/run_console.sh"
fi

bash -c 'exec -a skynet_console ./skynet ../etc/config.console'
