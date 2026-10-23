#!/bin/sh
. ~/demo-v2/hooks/lib.sh
ws=$(field .to.name)
info=$(omniwmctl query workspaces --workspace "$ws" \
  --fields display-name,window-counts --json)
name=$(echo "$info" | jq -r '.result.payload.workspaces[0].displayName')
n=$(echo "$info" | jq -r '.result.payload.workspaces[0].counts.total')
[ "$n" = 1 ] && noun=window || noun=windows
say "Now on $name, $n $noun"
