#!/usr/bin/env bash
set -euo pipefail

uid="${PUID:-1000}"
gid="${PGID:-1000}"
for n in "$uid" "$gid"; do
    if [[ ! "$n" =~ ^[1-9][0-9]{0,9}$ ]] || (( n > 4294967294 )); then
        echo "PUID and PGID must be positive numeric IDs (not root)." >&2
        exit 1
    fi
done

if [[ "$(id -u node)" != "$uid" ]] && getent passwd "$uid" >/dev/null; then
    echo "PUID=$uid already belongs to another account in this image." >&2
    exit 1
fi
if ! getent group "$gid" >/dev/null; then
    groupmod -g "$gid" node
fi
if [[ "$(id -u node):$(id -g node)" != "$uid:$gid" ]]; then
    usermod -u "$uid" -g "$gid" node
fi

# Only the private browser profile is migrated; never chown the host bind mount.
profile=/home/node/profile
if [[ "$(stat -c '%u:%g' "$profile")" != "$uid:$gid" ]]; then
    chown -Rh "$uid:$gid" "$profile"
fi
chown -h "$uid:$gid" /home/node /usr/share/novnc/mandatory.json

exec as-browser browser-watch
