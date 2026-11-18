#!/bin/sh
# Resolve the account set up at startup (including for later docker exec calls).
set -eu
if [ "$(id -u)" = 0 ]; then
    exec setpriv --reuid=node --regid="$(id -g node)" --clear-groups -- "$@"
fi
exec "$@"
