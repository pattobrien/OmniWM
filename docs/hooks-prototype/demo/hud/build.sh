#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEMO=/Users/runner/demo-v2
HUD="$DEMO/bin/hud"
LABEL=demo-v2.hud-trusted
JOB="gui/$(id -u)/$LABEL"
PLIST="$DEMO/logs/$LABEL.plist"
ERR="$DEMO/logs/hud-trusted.err"

mkdir -p "$DEMO/bin" "$DEMO/hud" "$DEMO/logs"
swiftc -O -o "$HUD" "$HERE/hud.swift"
"$HERE/grant-hud-tcc.sh" "$HUD"

plutil -create xml1 "$PLIST"
plutil -insert Label -string "$LABEL" "$PLIST"
plutil -insert ProgramArguments -json "[\"$HUD\", \"trusted\"]" "$PLIST"
plutil -insert StandardErrorPath -string "$ERR" "$PLIST"
plutil -insert RunAtLoad -bool true "$PLIST"
: > "$ERR"
if launchctl print "$JOB" > /dev/null 2>&1; then launchctl bootout "$JOB"; fi
launchctl bootstrap "gui/$(id -u)" "$PLIST"
status=""
for _ in $(seq 1 50); do
  status="$(launchctl print "$JOB" | sed -n 's/^[[:space:]]*last exit code = \([0-9][0-9]*\).*/\1/p')"
  [ -n "$status" ] && break
  sleep 0.1
done
launchctl bootout "$JOB"
rm "$PLIST"
[ "$status" = 0 ] || { echo "hud: self-check failed (exit ${status:-none}): $(cat "$ERR")" >&2; exit 1; }
echo "hud: built and trusted"
