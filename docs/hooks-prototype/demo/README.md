# Hooks demo, second take

One unattended take that shows five hook use cases. Each run has a title card, a live run with a
narration pane, and a result card. `record.sh` records the screen while `driver.sh` runs, then
writes the clip, the section timestamps, and one frame per section.

## Requirements

- macOS 27 with OmniWM Dev installed at `~/Applications/OmniWM Dev.app`, running, with IPC on and
  Accessibility granted. `omniwmctl ping` answers.
- Swift 6.4 (`swiftc`), Homebrew `jq` at `/opt/homebrew/bin/jq`, and `ffmpeg`. `record.sh` uses
  `/Users/runner/.dotnet/tools/ffmpeg`; edit `FF` if yours lives elsewhere.
- The user is `runner`. `hud.swift`, the hook scripts, and `hooks.toml` use `/Users/runner/demo-v2`.
- A single display at 1280x800 points (2560x1600 pixels). The cards and the narration pane scale to
  the screen width. `hud move` and `hud click` take global points.
- Screen Recording granted to the shell that runs `record.sh`.

## Install

1. Copy this directory to `/Users/runner/demo-v2`:

   ```sh
   rsync -a docs/hooks-prototype/demo/ /Users/runner/demo-v2/
   ```

2. Build `hud` and grant it Accessibility and PostEvent. `grant-hud-tcc.sh` writes the rows with
   `sudo sqlite3` into the system TCC database:

   ```sh
   bash /Users/runner/demo-v2/hud/build.sh
   ```

   It prints `hud: built and trusted`.

3. Stage the box:

   ```sh
   bash /Users/runner/demo-v2/setup.sh
   ```

   It quits Terminal and writes a `Demo` Terminal profile (Menlo 26, dark, no close prompt). It
   sets TextEdit to plain text at 26 pt. It sets `ApplePersistenceIgnoreState` for Terminal,
   TextEdit, Preview, and Safari, so a relaunch never restores windows from an earlier take. It
   kills any `hud ask` dialog an interrupted take left behind (`pkill -f "^hud ask "`). It names
   workspace `3` `logs` and sets Niri to three visible columns. It removes every `[[hooks]]` entry
   from the dev `settings.toml` and confirms the reload. It also starts `hud serve` under `nohup`
   if it is not already running. Rerunning it is safe.

## Record

```sh
bash /Users/runner/demo-v2/record.sh
```

The optional argument caps the recording in seconds (default 330). The driver takes about four
minutes. Do not touch the mouse or keyboard while it runs.

`record.sh` captures the screen with `ffmpeg -f avfoundation` (30 fps, `h264_videotoolbox`) into
`logs/take/raw.mov`, runs `driver.sh`, then runs `extract.sh`. ffmpeg stamps frames on the wall
clock, which `screencapture -v` did not. `extract.sh` finds the first dark frame of the intro card
(luma average below 45), lines it up with the driver's `reset` timestamp, and trims the clip with
`-c copy`. It then writes the timestamps, the frames, and copies of the logs.

Output lands in `/Users/runner/demo-v2/logs/take/`:

- `dryrun.mov` is the clip, trimmed to one second after the driver ends.
- `timestamps.txt` lists each section's start and end in clip seconds.
- `frames/<section>.png` is one full-resolution frame per section.
- `driver.log` is the driver's log, with window state after each step.
- `hook-invocations.log` has one line per hook run: time, script, and the payload.

To run the driver without recording, use `bash /Users/runner/demo-v2/driver.sh`.

## Files

- `hooks.toml` holds every `[[hooks]]` entry the demo uses.
- `apply-hooks.sh apply <hook>...` writes only the named entries into the dev `settings.toml`. It
  confirms the reload through a sentinel display name on workspace 9. `apply-hooks.sh print
  <hook>...` prints those entries for the title cards.
- `hooks/*.sh` are the hook scripts. `hooks/lib.sh` reads stdin once, logs the payload, and
  defines `field` and `say`.
- `cards/<run>.txt` are the first three lines of each title card. The driver appends the run's
  `settings.toml` entry and script. `cards/<run>-result*.txt` are the result cards. Each title
  card clears the narration pane and parks the cursor at (40, 400), clear of the card text.
  Parking is safe because the dev settings set `followsMouse = false`.
- `hooks/ask-admit.sh` remembers the pids it denied in `hud/denied-pids`. OmniWM asks again about
  30 ms after a deny, and the memory answers that second ask without a second dialog. The
  driver's reset removes the file.
- `hooks/announce.sh` queries the target workspace once as JSON and prints "Now on <name>, <n>
  window(s)". Its lines are short enough to fit the title card unclipped.
- `term/*.command` open the four Terminal windows: `work` and `notes` on workspace 1, and
  `unsaved draft` and `console` on workspace 4.
- `record.sh` runs the capture, the driver, and `extract.sh`.
- `stage/` holds the files the apps open.

## Runs

| Run | Hook | What happens |
| --- | --- | --- |
| 1a | `ask-admit` | Preview opens on workspace 1, the hook asks, Allow, and Preview tiles at the right end. |
| 1b | `ask-admit` | Same, but Deny. The window stays unmanaged and the script kills Preview. |
| 2a | none | `open -a Safari` and OmniWM follows Safari to workspace 2. |
| 2b | `stay-put` | `open -a Safari` is denied. The screen stays on 1 and typing continues in Terminal. |
| 3a | `confirm-close` | `console` closes the focused `unsaved draft`. The hook asks, Keep, and `hook_denied` prints. |
| 3b | `confirm-close` | Same, but Close. The window closes. |
| 4 | `route-logs` | `open -g -F` opens `[logs] server.log` in TextEdit. It lands on `logs`, and the screen stays on 1. |
| 5 | `announce` | Switching 1, then logs, then 1 posts "Now on <name>, <n> windows" after each switch. |

`logs` is a display name. Raw workspace names must be positive integers, so the hook answers
`{"workspace": "3"}`.

Run 4 uses TextEdit because it has no windows when the run starts. `PlacementResolver` ignores the
hook's workspace for an app that already has windows. `-F` stops TextEdit from reopening documents
from an earlier take.
