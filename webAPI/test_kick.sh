#!/bin/bash
HOST=${1:-127.0.0.1}
PORT=${2:-8900}
ACC_ID=${3:-1018168}
SERVER_ID=${4:-1}
API_KEY=${5:-${WEB_API_KEY:-}}

URL="http://${HOST}:${PORT}/api/player/kick"
BODY="{\"acc_id\":${ACC_ID},\"server_id\":${SERVER_ID}}"

CURL_OPTS=(-s -w "\nHTTP_CODE:%{http_code}\n" -X POST -H "Content-Type: application/json" -d "$BODY")
if [ -n "$API_KEY" ]; then
	CURL_OPTS+=(-H "X-Api-Key: $API_KEY")
fi

curl "${CURL_OPTS[@]}" "$URL"
