#!/bin/sh
set -eu
node /local/install.cjs
exec node --watch /local/worker-start.mjs
