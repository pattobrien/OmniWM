#!/usr/bin/env bash
set -euo pipefail
DEMO=/Users/runner/demo-v2
CTL="$HOME/Applications/OmniWM Dev.app/Contents/MacOS/omniwmctl"
JQ=/opt/homebrew/bin/jq
F="$HOME/.config/omniwm-dev/settings.toml"
LOGS="$DEMO/logs"
mode="${1:?usage: apply-hooks.sh print|apply [hook-name...]}"
shift

select_hooks() {
  awk -v names="$*" '
    BEGIN { n = split(names, want, " ") }
    function flush(   i, keep) {
      keep = 0
      for (i = 1; i <= n; i++) if (index(entry, "/hooks/" want[i] ".sh\"")) keep = 1
      if (keep) printf "%s%s", (printed++ ? "\n" : ""), entry
      entry = ""
    }
    /^\[\[hooks\]\]$/ && entry != "" { flush() }
    NF || entry != "" { entry = entry $0 "\n" }
    END { flush() }
  ' "$DEMO/hooks.toml" | awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }'
}

if [ "$mode" = print ]; then
  select_hooks "$@"
  exit 0
fi
[ "$mode" = apply ]

block="$(mktemp)"
next="$(mktemp "$HOME/.config/omniwm-dev/.settings.next.XXXXXX")"
trap 'rm -f "$block" "$next" "$next.body"' EXIT
select_hooks "$@" > "$block"
sentinel="hooks-$(date +%s%N | shasum -a 256 | cut -c1-8)"
want="$(grep -c '^\[\[hooks\]\]$' "$block" || true)"

awk -v sentinel="$sentinel" '
function flush(   i) {
  if (n == 0) return
  if (buf[1] ~ /^\[\[?hooks[].]/) { n = 0; return }
  if (buf[1] == "[[workspaces]]" && has9) {
    print buf[1]; print "displayName = \"" sentinel "\""
    for (i = 2; i <= n; i++) if (buf[i] !~ /^displayName = /) print buf[i]
  } else if (buf[1] == "[[workspaces]]" && has3) {
    print buf[1]; print "displayName = \"logs\""
    for (i = 2; i <= n; i++) if (buf[i] !~ /^displayName = /) print buf[i]
  } else if (buf[1] == "[niri]") {
    for (i = 1; i <= n; i++) {
      if (buf[i] ~ /^visibleContainerCount = /) print "visibleContainerCount = 3"
      else if (buf[i] ~ /^defaultContainerPrimarySpan = /) print "defaultContainerPrimarySpan = 0.3333333333333333"
      else print buf[i]
    }
  } else { for (i = 1; i <= n; i++) print buf[i] }
  n = 0
}
/^\[/ { flush(); has9 = 0; has3 = 0 }
{ buf[++n] = $0; if ($0 == "name = \"9\"") has9 = 1; if ($0 == "name = \"3\"") has3 = 1 }
END { flush() }
' "$F" > "$next.body"
awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }' "$next.body" > "$next"
if [ -s "$block" ]; then
  printf '\n' >> "$next"
  cat "$block" >> "$next"
fi
mkdir -p "$LOGS"
cp "$F" "$LOGS/settings.before-apply.toml"
mv "$next" "$F"

displayname9() { "$CTL" query workspaces --workspace 9 --json | "$JQ" -r '.result.payload.workspaces[0].displayName'; }
got=""
for _ in $(seq 1 40); do
  got="$(displayname9)"
  [ "$got" = "$sentinel" ] && break
  sleep 0.25
done
[ "$got" = "$sentinel" ] || { echo "apply-hooks: reload not confirmed, workspace 9 displayName=$got expected=$sentinel" >&2; exit 1; }
"$CTL" workspace rename 9 "" > /dev/null
for _ in $(seq 1 40); do
  got="$(displayname9)"
  [ "$got" = 9 ] && break
  sleep 0.25
done
sleep 0.5
entries="$(grep -c '^\[\[hooks\]\]$' "$F" || true)"
[ "$got" = 9 ] && [ "$entries" = "$want" ] || { echo "apply-hooks: after restoring workspace 9, displayName=$got and $entries [[hooks]] entries (want $want)" >&2; exit 1; }
echo "apply-hooks: active hooks [${*:-none}], $entries entries, reload confirmed by $sentinel"
