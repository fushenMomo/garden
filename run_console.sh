#!/bin/bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
HIST="$HOME/.mirage_console_history"
INPUTRC="$ROOT/etc/console.inputrc"
cd "$ROOT/skynet" || exit 1

if [ -t 0 ] && command -v rlwrap >/dev/null 2>&1; then
  export RLWRAP=1
  exec rlwrap \
    -H "$HIST" \
    -f "$INPUTRC" \
    -D 1 \
    bash -c 'exec -a skynet_console ./skynet ../etc/config.console'
fi

if [ -t 0 ]; then
  echo "rlwrap not found, run without command history. install: sudo apt install rlwrap" >&2
fi
exec bash -c 'exec -a skynet_console ./skynet ../etc/config.console'
