#!/bin/sh
set -eu
rm -f /tmp/local-tours-ready
node /local/install.cjs
npm run build:lib
node /local/tours-ready.cjs --build-only
touch /tmp/local-tours-ready
npm run build:lib:watch &
watch_pid=$!
trap 'kill "$watch_pid" 2>/dev/null || true' EXIT INT TERM
npm start -- --strictPort
