#!/usr/bin/env bash
set -euo pipefail
umask 077
export LC_ALL=C

state=/tmp/browser-watch-recorder
output=/recordings
display=:99.0

fail() {
    printf 'Recorder: %s\n' "$*" >&2
    exit 1
}

usage='Usage: record start [seconds] | record status | record stop'
case "${1:-}" in
    start) (( $# <= 2 )) || fail "$usage" ;;
    status|stop) (( $# == 1 )) || fail "$usage" ;;
    *) fail "$usage" ;;
esac

mkdir -p -m 700 "$state"
# Serialize commands; only the background capture inherits the second lock.
exec 8>"$state/command.lock"
flock -w 5 8 || fail "Another recorder command is busy."
exec 9>"$state/capture.lock"
active=false
flock -n 9 || active=true

case "$1" in
    status)
        if $active; then
            printf 'Recording: %s\n' "$(<"$state/file")"
        else
            printf 'Not recording.\n'
            if [[ -f "$state/file" && -s "$(<"$state/file")" ]]; then
                printf 'Last file: %s\n' "$(<"$state/file")"
            fi
            if [[ -s "$state/ffmpeg.log" ]]; then
                cat "$state/ffmpeg.log" >&2
            fi
        fi
        exit 0
        ;;
    stop)
        if ! $active; then
            printf 'Not recording.\n'
            exit 0
        fi
        # FFmpeg's q command finalizes the MP4. Open the FIFO read/write so
        # stop cannot block opening it if FFmpeg has already exited.
        exec 7<>"$state/input"
        printf q >&7
        flock -w 8 9 || fail "FFmpeg has not stopped yet. Check record status."
        file="$(<"$state/file")"
        [[ -s "$file" ]] || fail "No video was saved. Check record status."
        printf 'Stopped: %s\n' "$file"
        exit 0
        ;;
    start)
        $active && fail "A recording is already running."
        ;;
esac

duration="${2-1800}"
max_mib="${RECORDING_MAX_MIB:-2048}"
if [[ ! "$duration" =~ ^[1-9][0-9]{0,3}$ ]] || (( duration > 1800 )); then
    fail "Recording duration must be an integer from 1 to 1800 seconds."
fi
if [[ ! "$max_mib" =~ ^[1-9][0-9]{0,5}$ ]] || (( max_mib < 32 )); then
    fail "RECORDING_MAX_MIB must be an integer from 32 to 999999."
fi
[[ -d "$output" && -w "$output" ]] \
    || fail "Cannot write to /recordings. Check the owner of ./recordings on the Docker host (see README)."

# Enforce the directory's budget and leave headroom for MP4 finalization.
mib=1048576
used="$(du -sb -- "$output" | cut -f1)"
free="$(df -B1 --output=avail -- "$output" | tail -n 1)"
remaining=$((max_mib * mib - used))
if (( free < remaining )); then
    remaining=$free
fi
if (( remaining <= 16 * mib )); then
    fail "Not enough room for a new recording. Check free disk space or move old recordings."
fi
file_limit=$((remaining - 16 * mib))

timeout 3s xdpyinfo -display "$display" >/dev/null 2>&1 \
    || fail "Display $display is unavailable. Wait for Browser Watch to be ready."
[[ -p "$state/input" ]] || mkfifo "$state/input"
file="$output/browser-watch-$(date -u +%Y%m%dT%H%M%S-%NZ).mp4"
printf '%s\n' "$file" >"$state/file"

# Detach from docker exec. A wall-clock timeout still stops a stalled capture.
setsid timeout --signal=TERM --kill-after=5s "${duration}s" \
    ffmpeg -hide_banner -loglevel error -stdin -n \
    -f x11grab -framerate 15 -i "$display" -an \
    -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' \
    -c:v libx264 -preset veryfast -threads 2 -pix_fmt yuv420p \
    -crf 23 -maxrate 3M -bufsize 6M -g 30 \
    -movflags +frag_keyframe+empty_moov+default_base_moof -flush_packets 1 \
    -t "$duration" -fs "$file_limit" "$file" \
    0<>"$state/input" >"$state/ffmpeg.log" 2>&1 8>&- &

# Don't close the caller's terminal until FFmpeg is detached and writing.
exec 9>&-
exec 9>"$state/capture.lock"
for ((attempt = 0; attempt < 60; attempt++)); do
    if [[ -s "$file" ]]; then
        printf 'Recording: %s (up to %s seconds)\n' "$file" "$duration"
        exit 0
    fi
    flock -n 9 && break
    sleep 0.05
done
cat "$state/ffmpeg.log" >&2
fail "FFmpeg did not start writing a video. Check record status."
