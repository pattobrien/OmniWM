#!/usr/bin/env bash
set -uo pipefail
DEMO=/Users/runner/demo-v2
CTL="$HOME/Applications/OmniWM Dev.app/Contents/MacOS/omniwmctl"
JQ=/opt/homebrew/bin/jq
HUD="$DEMO/bin/hud"
LOGS="$DEMO/logs"
CARD="$DEMO/hud/card.txt"
NARRATION="$DEMO/hud/narration.txt"
SECTIONS="$LOGS/sections.tsv"
SHOTS="$LOGS/shots.tsv"
: > "$SECTIONS"
: > "$SHOTS"
: > "$LOGS/hook-invocations.log"
exec > >(tee "$LOGS/driver.log") 2>&1

now() { date +%s.%N; }
log() { printf '%s %s\n' "$(now)" "$*"; }
section() { printf '%s\t%s\t%s\n' "$1" "$(now)" "$2" >> "$SECTIONS"; log "== $1 $2"; }
shot() { printf '%s\t%s\n' "$1" "$(now)" >> "$SHOTS"; log "shot $1"; }
say() { printf '%s\n' "$*" >> "$NARRATION"; log "narration: $*"; }
hold() { sleep "$1"; }
ctl() {
  local out rc
  out="$("$CTL" "$@" 2>&1)"
  rc=$?
  case "$rc:$out" in
    0:*) log "omniwmctl $*" ;;
    *no_change*) log "omniwmctl $* (no change)" ;;
    *) log "omniwmctl $* failed with $rc: $out" ;;
  esac
}

ids() { "$CTL" query windows --bundle-id "$1" --json | "$JQ" -r '.result.payload.windows[].id'; }
id_titled() { "$CTL" query windows --bundle-id "$1" --json | "$JQ" -r --arg t "$2" '[.result.payload.windows[] | select(.title == $t)][0].id // empty'; }
count_on() { "$CTL" query windows --workspace "$1" --json | "$JQ" '.result.payload.windows | length'; }
current_ws() { "$CTL" query workspaces --current --json | "$JQ" -r '.result.payload.workspaces[0].rawName'; }
front_app() { lsappinfo info -only name "$(lsappinfo front)" | sed -n '1s/^"\([^"]*\)".*/\1/p'; }
state() {
  log "state $1: current=$(current_ws) front=$(front_app)"
  "$CTL" query windows --json | "$JQ" -c '.result.payload.windows[] | {id, app: .app.name, title, ws: .workspace.rawName, mode, isFocused, frame}'
}

wait_for() {
  local tries="$1"
  shift
  for _ in $(seq 1 "$tries"); do
    "$@" && return 0
    sleep 0.25
  done
  log "timed out waiting for: $*"
  return 1
}
has_window() { [ -n "$(id_titled "$1" "$2")" ]; }
no_window() { [ -z "$(id_titled "$1" "$2")" ]; }
dialog_up() { [ -s "$DEMO/hud/dialog.json" ]; }
dialog_gone() { [ ! -e "$DEMO/hud/dialog.json" ]; }
app_gone() { ! pgrep -x "$1" > /dev/null; }
terminals_are() { [ "$("$CTL" query windows --bundle-id com.apple.Terminal --json | "$JQ" '.result.payload.windows | length')" = "$1" ]; }
clear_dialogs() {
  if pgrep -f "^hud ask " > /dev/null; then
    log "a hud ask dialog was still open: $(cat "$DEMO/hud/dialog.json" 2>/dev/null)"
    pkill -f "^hud ask "
  fi
  wait_for 20 dialog_gone || rm -f "$DEMO/hud/dialog.json"
}
on_workspace() { [ "$(current_ws)" = "$1" ]; }

card_shown_at=0
title_card() {
  local run="$1" hook="${2:-}"
  section "$run-title" "title card"
  clear_dialogs
  : > "$NARRATION"
  {
    sed -n 1,3p "$DEMO/cards/$run.txt"
    if [ -n "$hook" ]; then
      printf '\n// settings.toml\n'
      bash "$DEMO/apply-hooks.sh" print "$hook"
      printf -- '---\n// hooks/%s.sh\n' "$hook"
      cat "$DEMO/hooks/$hook.sh"
    fi
  } > "$CARD"
  card_shown_at="$(now)"
  "$HUD" move 40 400 &
  hold 1
  shot "$run-title"
}
card_hold() {
  local left
  left="$(awk -v a="$card_shown_at" -v b="$(now)" -v want="$1" 'BEGIN { d = want - (b - a); print (d > 0 ? d : 0) }')"
  sleep "$left"
  : > "$NARRATION"
  : > "$CARD"
  hold 1
}
result_card() {
  local run="$1" text="$2"
  section "$run-result" "result card"
  printf '%s\n' "$text" > "$CARD"
  card_shown_at="$(now)"
  hold 1
  shot "$run-result"
}

press() {
  local button="$1" label="$2" x y
  printf '%s\n' "$button" > "$DEMO/hud/choice"
  wait_for 60 dialog_up || return 1
  log "dialog: $(cat "$DEMO/hud/dialog.json")"
  hold 2
  read -r x y < <("$JQ" -r --arg b "$button" '.buttons[$b] | "\(.x) \(.y)"' "$DEMO/hud/dialog.json")
  "$HUD" move "$x" "$y"
  shot "$label"
  hold 1
  "$HUD" click "$x" "$y"
  log "clicked $button at $x $y"
  wait_for 20 dialog_gone
}

open_term() {
  local role="$1" title="$2"
  open -a Terminal "$DEMO/term/$role.command"
  wait_for 40 has_window com.apple.Terminal "$title"
}

reset_stage() {
  section reset "intro card while the stage resets"
  printf '%s\n' \
    "OmniWM hooks: your script gets a say" \
    "Before OmniWM places a window, follows an app, or runs a command" \
    "Five things a user wants, each shown live" > "$CARD"
  card_shown_at="$(now)"
  : > "$NARRATION"
  rm -f "$DEMO/hud/dialog.json" "$DEMO/hud/choice" "$DEMO/hud/denied-pids"
  pkill -f "^hud ask "
  for app in Preview TextEdit Terminal Safari; do pkill -x "$app"; done
  for app in Preview TextEdit Terminal Safari; do wait_for 40 app_gone "$app"; done
  rm -rf "$HOME/Library/Saved Application State/com.apple.Terminal.savedState" \
    "$HOME"/Library/Containers/com.apple.{Preview,TextEdit,Safari}/Data/Library/Saved\ Application\ State/*.savedState
  bash "$DEMO/apply-hooks.sh" apply
  ctl workspace focus-name 1

  open -F -a Safari "file://$DEMO/stage/safari.html"
  wait_for 40 has_window com.apple.Safari "Safari on workspace 2"
  ctl window move-to-workspace "$(id_titled com.apple.Safari "Safari on workspace 2")" 2

  ctl workspace focus-name 4
  open_term draft "unsaved draft"
  open_term console console
  ctl window move-to-workspace "$(id_titled com.apple.Terminal "unsaved draft")" 4
  ctl window move-to-workspace "$(id_titled com.apple.Terminal console)" 4
  ctl window move-column-to-first "$(id_titled com.apple.Terminal "unsaved draft")"

  ctl workspace focus-name 1
  open_term work work
  open_term notes notes
  ctl window move-to-workspace "$(id_titled com.apple.Terminal work)" 1
  ctl window move-to-workspace "$(id_titled com.apple.Terminal notes)" 1
  ctl window move-column-to-first "$(id_titled com.apple.Terminal work)"
  for id in $("$CTL" query windows --bundle-id com.apple.Terminal --json | "$JQ" -r '.result.payload.windows | (map(select(.title as $t | ["work", "notes", "console", "unsaved draft"] | index($t) | not)) + (map(select(.title as $t | ["work", "notes", "console", "unsaved draft"] | index($t))) | group_by(.title) | map(.[1:]) | add // [])) | .[].id'); do
    ctl window close "$id"
  done
  wait_for 40 terminals_are 4
  ctl workspace focus-name 1
  hold 1
  state "after reset"
  shot reset
  card_hold 7
}

focus_on_1() {
  ctl workspace focus-name 1
  ctl window focus "$(id_titled "$1" "$2")"
  hold 1
}

run_1() {
  local run="$1" button="$2"
  title_card "$run" ask-admit
  pkill -x Preview
  wait_for 40 app_gone Preview
  focus_on_1 com.apple.Terminal notes
  bash "$DEMO/apply-hooks.sh" apply ask-admit
  card_hold "$3"

  section "$run-ask" "Preview opens, the hook asks"
  say "Windows on workspace 1: $(count_on 1)"
  hold 2.5
  say "Opening a picture in Preview"
  open -F -a Preview "$DEMO/stage/photo.png"
  press "$button" "$run-ask"
  section "$run-effect" "after $button"
  if [ "$button" = Deny ]; then wait_for 40 app_gone Preview; fi
  hold 2.5
  state "$run after $button"
  say "Windows on workspace 1: $(count_on 1)"
  hold 1
  shot "$run-effect"
  hold 2
}

run_2a() {
  title_card 2a
  focus_on_1 com.apple.Terminal work
  bash "$DEMO/apply-hooks.sh" apply
  card_hold 7

  section 2a-run "Safari activates with no hook"
  say "Typing in Terminal on workspace 1"
  "$HUD" type 'echo "drafting on workspace 1"\n'
  hold 2
  say "Something activates Safari: open -a Safari"
  open -a Safari
  hold 3
  state "2a after activation"
  say "Now on workspace $(current_ws)"
  hold 1
  shot 2a-run
  hold 2
  result_card 2a "$(cat "$DEMO/cards/2a-result.txt")"
  ctl workspace focus-name 1
  hold 3
}

run_2b() {
  title_card 2b stay-put
  focus_on_1 com.apple.Terminal work
  bash "$DEMO/apply-hooks.sh" apply stay-put
  card_hold 9

  section 2b-run "Safari activates, the hook denies"
  say "Typing in Terminal on workspace 1"
  "$HUD" type 'echo "drafting on workspace 1"\n'
  hold 2
  say "Something activates Safari: open -a Safari"
  open -a Safari
  hold 3
  shot 2b-run
  section 2b-typing "typing after the deny"
  say "Still typing"
  "$HUD" type 'echo "still here, still typing"\n'
  hold 1.5
  local front ws
  front="$(front_app)"
  ws="$(current_ws)"
  state "2b after typing"
  say "On workspace $ws, keys went to $front"
  hold 1
  shot 2b-typing
  hold 2
  if [ "$front" = Terminal ] && [ "$ws" = 1 ]; then
    result_card 2b "$(cat "$DEMO/cards/2b-result.txt")"
  else
    result_card 2b "$(printf "$(cat "$DEMO/cards/2b-result-unfocused.txt")" "$ws" "$front")"
  fi
  hold 3
}

draft_center() {
  "$CTL" query windows --bundle-id com.apple.Terminal --json \
    | "$JQ" -r '[.result.payload.windows[] | select(.title == "unsaved draft")][0].frame | "\((.x + .width / 2) | floor) \((.y + .height / 2) | floor)"'
}

run_3() {
  local run="$1" button="$2" x y
  title_card "$run" confirm-close
  ctl workspace focus-name 4
  ctl window focus "$(id_titled com.apple.Terminal console)"
  hold 1
  bash "$DEMO/apply-hooks.sh" apply confirm-close
  card_hold "$3"

  section "$run-ask" "console asks OmniWM to close the focused window"
  say "Workspace 4: 'unsaved draft' and a console"
  hold 2.5
  say "Console: close the focused window in 3 s"
  "$HUD" type 'sleep 3; omniwmctl command close-focused-window\n'
  say "Click 'unsaved draft' to focus it"
  read -r x y < <(draft_center)
  "$HUD" click "$x" "$y"
  press "$button" "$run-ask"
  section "$run-effect" "after $button"
  if [ "$button" = Close ]; then wait_for 20 no_window com.apple.Terminal "unsaved draft"; fi
  hold 2.5
  state "$run after $button"
  say "Windows on workspace 4: $(count_on 4)"
  hold 1
  shot "$run-effect"
  hold 2
}

run_4() {
  title_card 4 route-logs
  local old
  old="$(id_titled com.apple.TextEdit "[logs] server.log")"
  [ -z "$old" ] || ctl window close "$old"
  focus_on_1 com.apple.Terminal work
  bash "$DEMO/apply-hooks.sh" apply route-logs
  card_hold 9

  section 4-run "a [logs] window opens in the background"
  say "On workspace 1, $(count_on 1) windows"
  hold 2.5
  say "A script opens '[logs] server.log' (open -g)"
  open -g -F -a TextEdit "$DEMO/stage/[logs] server.log"
  wait_for 40 has_window com.apple.TextEdit "[logs] server.log"
  hold 2.5
  state "4 after open"
  say "Still on workspace $(current_ws), $(count_on 1) windows"
  hold 1
  shot 4-run
  hold 2
  section 4-switch "switch to logs"
  say "Switching to logs"
  ctl workspace focus-name logs
  hold 2
  say "logs holds: $("$CTL" query windows --workspace 3 --json | "$JQ" -r '[.result.payload.windows[].title] | join(", ")')"
  hold 1
  shot 4-switch
  hold 2
  result_card 4 "$(cat "$DEMO/cards/4-result.txt")"
  ctl workspace focus-name 1
  hold 3
}

run_5() {
  title_card 5 announce
  focus_on_1 com.apple.Terminal work
  bash "$DEMO/apply-hooks.sh" apply announce
  card_hold 9

  section 5-run "switch 1 to logs to 1"
  say "Switching 1 -> logs"
  ctl workspace focus-name logs
  hold 1.5
  shot 5-run
  hold 2
  section 5-back "switch back to 1"
  say "Switching logs -> 1"
  ctl workspace focus-name 1
  hold 1.5
  shot 5-back
  hold 2
  result_card 5 "$(cat "$DEMO/cards/5-result.txt")"
  hold 3
}

reset_stage

run_1 1a Allow 10
result_card 1a "$(cat "$DEMO/cards/1a-result.txt")"
pkill -x Preview
hold 3
run_1 1b Deny 7
result_card 1b "$(cat "$DEMO/cards/1b-result.txt")"
hold 3

run_2a
run_2b

run_3 3a Keep 10
result_card 3a "$(cat "$DEMO/cards/3a-result.txt")"
hold 3
run_3 3b Close 7
if has_window com.apple.Terminal "unsaved draft"; then
  result_card 3b "$(cat "$DEMO/cards/3b-result-conflict.txt")"
else
  result_card 3b "$(cat "$DEMO/cards/3b-result.txt")"
fi
hold 3

run_4
run_5

section end "clear the stage"
: > "$CARD"
: > "$NARRATION"
bash "$DEMO/apply-hooks.sh" apply
log "driver done"
