PATH=/Users/runner/demo-v2/bin:/opt/homebrew/bin:/usr/bin:/bin
payload=$(cat)
printf '%s %s %s\n' "$(date +%s.%N)" "${0##*/}" "$(printf '%s' "$payload" | jq -c .)" >> /Users/runner/demo-v2/logs/hook-invocations.log
field() { printf '%s' "$payload" | jq -r "$1 // empty"; }
say() { printf '%s\n' "$*" >> /Users/runner/demo-v2/hud/narration.txt; }
