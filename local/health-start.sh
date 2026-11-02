#!/bin/sh
set -eu
rm -f /tmp/local-health-ready
node /local/install.cjs
npm run build:lib
node /local/health-ready.cjs --build-only
touch /tmp/local-health-ready
npm run build:lib:watch &
watch_pid=$!
trap 'kill "$watch_pid" 2>/dev/null || true' EXIT INT TERM
npm start
