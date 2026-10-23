#!/usr/bin/env bash
set -euo pipefail
DEMO=/Users/runner/demo-v2
LOGS="$DEMO/logs"
FF=/Users/runner/.dotnet/tools/ffmpeg
TAKE="$LOGS/take"
cap="${1:-330}"

rm -rf "$TAKE"
mkdir -p "$TAKE/frames"
caffeinate -u -t 2
sleep 1
"$FF" -nostdin -hide_banner -loglevel error -f avfoundation -framerate 30 -capture_cursor 1 -i "Capture screen 0:none" \
  -t "$cap" -c:v h264_videotoolbox -b:v 16M -pix_fmt yuv420p "$TAKE/raw.mov" &
ff=$!
sleep 2
rc=0
bash "$DEMO/driver.sh" || rc=$?
echo "$rc" > "$LOGS/driver.rc"
sleep 1
kill -TERM "$ff"
wait "$ff" || true
bash "$DEMO/extract.sh"
exit "$rc"
