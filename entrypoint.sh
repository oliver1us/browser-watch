#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=:99
profile="$HOME/profile"
resolution="${SCREEN_RESOLUTION:-1600x1000}"
children=()
chromium_pid=""

if [[ ! "$resolution" =~ ^[1-9][0-9]{0,3}x[1-9][0-9]{0,3}$ ]]; then
    echo "SCREEN_RESOLUTION must be WIDTHxHEIGHT, with each dimension from 1 to 9999 (e.g. 1920x1080)." >&2
    exit 1
fi

case "${VNC_VIEW_ONLY:-on}" in
    on) vnc_options=(-viewonly); view_only=true ;;
    off) vnc_options=(); view_only=false ;;
    *) echo "VNC_VIEW_ONLY must be 'on' or 'off'." >&2; exit 1 ;;
esac

# Keep the noVNC interface in sync with x11vnc, regardless of saved settings or URL flags.
printf '{"view_only": %s}\n' "$view_only" > /usr/share/novnc/mandatory.json

cleanup() {
    trap - EXIT
    trap '' INT TERM
    if [[ -n "$chromium_pid" ]]; then
        kill -TERM "$chromium_pid" 2>/dev/null || true
        wait "$chromium_pid" 2>/dev/null || true
    fi
    if ((${#children[@]})); then
        kill -TERM "${children[@]}" 2>/dev/null || true
        wait "${children[@]}" 2>/dev/null || true
    fi
}

wait_ready() {
    local label="$1" pid="$2"
    shift 2
    for ((attempt = 0; attempt < 60; attempt++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        if "$@" >/dev/null 2>&1; then
            return
        fi
        sleep 0.25
    done
    echo "$label failed to start." >&2
    return 1
}

trap cleanup EXIT
trap 'exit 0' INT TERM

# This container exclusively owns this display and profile.
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 \
    "$profile/SingletonLock" "$profile/SingletonSocket" "$profile/SingletonCookie"

Xvfb "$DISPLAY" -screen 0 "${resolution}x24" -nolisten tcp &
children+=("$!")
wait_ready Xvfb "${children[-1]}" xdpyinfo

x11vnc -display "$DISPLAY" -localhost -rfbport 5900 -nopw "${vnc_options[@]}" -shared -forever -quiet &
children+=("$!")
websockify --web /usr/share/novnc 0.0.0.0:6080 127.0.0.1:5900 &
children+=("$!")

case "${CHROMIUM_SANDBOX:-on}" in
    on) sandbox=() ;;
    off)
        echo "Warning: the Chromium sandbox is disabled." >&2
        sandbox=(--no-sandbox)
        ;;
    *) echo "CHROMIUM_SANDBOX must be 'on' or 'off'." >&2; exit 1 ;;
esac

# Chromium owns the browser. Both MCPs attach to it over container loopback.
chromium "${sandbox[@]}" \
    --user-data-dir="$profile" \
    --remote-debugging-port=9222 \
    --no-first-run \
    --no-default-browser-check \
    --window-position=0,0 \
    --window-size="${resolution/x/,}" &
chromium_pid="$!"
wait_ready Chromium "$chromium_pid" curl -fsS --max-time 1 "$BU_CDP_URL/json/version"

playwright-mcp --host 0.0.0.0 --port 8931 \
    --allowed-hosts '127.0.0.1:8931,localhost:8931,browser-watch:8931' \
    --cdp-endpoint "$BU_CDP_URL" &
children+=("$!")

wait -n "$chromium_pid" "${children[@]}" || true
echo "A Browser Watch service exited. Restarting the container." >&2
exit 1
