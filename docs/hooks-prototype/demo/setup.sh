#!/usr/bin/env bash
set -euo pipefail
DEMO=/Users/runner/demo-v2
CTL="$HOME/Applications/OmniWM Dev.app/Contents/MacOS/omniwmctl"
JQ=/opt/homebrew/bin/jq
HUD="$DEMO/bin/hud"

mkdir -p "$DEMO/hud" "$DEMO/logs" "$DEMO/bin"
[ -x "$HUD" ] || { echo "setup: $HUD is missing; build it with hud/build.sh first" >&2; exit 1; }
"$HUD" trusted
ln -sf "$CTL" "$DEMO/bin/omniwmctl"
chmod +x "$DEMO"/*.sh "$DEMO"/hooks/*.sh "$DEMO"/term/*.command
[ -f "$DEMO/stage/photo.png" ] || sips -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns --out "$DEMO/stage/photo.png" > /dev/null

pkill -x Terminal || true
for _ in $(seq 1 50); do pgrep -x Terminal > /dev/null || break; sleep 0.1; done
osascript -l JavaScript <<'JXA'
ObjC.import('AppKit')
const prefs = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.Terminal')
const all = $.NSMutableDictionary.dictionaryWithDictionary(prefs.dictionaryForKey('Window Settings'))
const profile = $.NSMutableDictionary.dictionaryWithDictionary(all.objectForKey('Clear Dark'))
const font = $.NSFont.fontWithNameSize('Menlo-Regular', 26)
profile.setObjectForKey($.NSKeyedArchiver.archivedDataWithRootObjectRequiringSecureCodingError(font, false, null), 'Font')
profile.setObjectForKey('Demo', 'name')
profile.setObjectForKey(0, 'warnOnShellCloseAction')
profile.setObjectForKey(0, 'shellExitAction')
for (const key of ['ShowActiveProcessInTitle', 'ShowActiveProcessArgumentsInTitle', 'ShowCommandKeyInTitle',
  'ShowDimensionsInTitle', 'ShowShellCommandInTitle', 'ShowTTYNameInTitle', 'ShowWindowSettingsNameInTitle',
  'ShowRepresentedURLInTitle', 'ShowRepresentedURLPathInTitle', 'ShowWorkingDirectoryInTitle']) {
  profile.setObjectForKey(false, key)
}
all.setObjectForKey(profile, 'Demo')
prefs.setObjectForKey(all, 'Window Settings')
prefs.setObjectForKey('Demo', 'Default Window Settings')
prefs.setObjectForKey('Demo', 'Startup Window Settings')
prefs.synchronize
JXA
defaults write -g NSQuitAlwaysKeepsWindows -bool false
for app in Terminal TextEdit Preview Safari; do defaults write "com.apple.$app" ApplePersistenceIgnoreState -bool true; done
pkill -f "^hud ask " || true
defaults write com.apple.TextEdit RichText -bool false
defaults write com.apple.TextEdit NSFixedPitchFont Menlo-Regular
defaults write com.apple.TextEdit NSFixedPitchFontSize -int 26

bash "$DEMO/apply-hooks.sh" apply
[ "$("$CTL" query workspaces --workspace 3 --json | "$JQ" -r '.result.payload.workspaces[0].displayName')" = logs ] || { echo "setup: workspace 3 is not shown as logs" >&2; exit 1; }

if ! pgrep -f "$HUD serve" > /dev/null; then
  : > "$DEMO/hud/card.txt"
  : > "$DEMO/hud/narration.txt"
  nohup "$HUD" serve >> "$DEMO/logs/hud-serve.log" 2>&1 < /dev/null &
  disown
  sleep 1
fi
pgrep -f "$HUD serve" > /dev/null
echo "setup: Terminal profile Demo at Menlo 26, workspace 3 shown as logs, no hooks active, hud serve pid $(pgrep -f "$HUD serve")"
