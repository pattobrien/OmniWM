#!/bin/sh
. ~/demo-v2/hooks/lib.sh
app=$(field .window.app_name)
ws=$(field .active_workspace.name)
pid=$(field .window.pid)
denied=~/demo-v2/hud/denied-pids
if grep -qx "$pid" "$denied" 2>/dev/null; then
  echo "denied earlier" >&2
  exit 2
fi
msg="$app wants a window on workspace $ws."
if hud ask "$msg" Allow Deny >/dev/null; then
  say "Hook: Allow, exit 0"
  exit 0
fi
echo "$pid" >> "$denied"
say "Hook: Deny, exit 2. Left unmanaged."
(sleep 2; kill $pid; say "Script closed $app") \
  >/dev/null 2>&1 &
echo "the user denied it" >&2
exit 2
