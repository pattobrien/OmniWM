#!/bin/sh
. ~/demo-v2/hooks/lib.sh
title=$(field .focused_window.title)
case "$title" in
  *"unsaved draft"*) ;;
  *) exit 0 ;;
esac
if hud ask "Close '$title'?" Keep Close >/dev/null
then
  say "Hook: Keep, exit 2"
  echo "Kept '$title' open" >&2
  exit 2
fi
say "Hook: Close, exit 0"
exit 0
