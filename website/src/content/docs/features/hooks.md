---
title: Hooks
description: Run your own scripts to allow, deny, or change workspace switches, window placement, and commands, and to react after the workspace changes.
sidebar:
  order: 9
---

Hooks run your own shell commands at four points in OmniWM's event flow, the way Claude Code hooks run around an agent's tool calls. A blocking hook can allow, deny, or change what OmniWM is about to do, and a post hook runs after a change has happened.

Unreleased: available when building from `main`.

## Events

| Event | When it runs | Kind | What the script can return |
| --- | --- | --- | --- |
| `pre-workspace-activation` | Another app or macOS activates a managed window on a workspace that is not showing, and OmniWM is about to switch to that workspace. | Blocking | Allow or deny. |
| `pre-window-admission` | A new window appears. OmniWM has applied `[[appRules]]` but has not placed the window yet. | Blocking | Allow, deny, or a JSON object that sets the workspace or floating state. |
| `pre-command` | A hotkey, an `omniwmctl` request, or a workspace-bar widget asks OmniWM to run a command. | Blocking | Allow or deny. |
| `post-workspace-change` | The active workspace on the interaction monitor changed. | Post | Nothing. OmniWM ignores the output and the exit status. |

A deny on `pre-workspace-activation` keeps the current workspace on screen. The activated window stays on its own workspace, and OmniWM moves focus back to the active workspace. If the active workspace is empty, OmniWM takes focus itself.

A deny on `pre-window-admission` leaves the window unmanaged.

A deny on `pre-command` skips the command.

## Configure hooks

Add one `[[hooks]]` entry to `settings.toml` for each event and matcher. List the entry's commands as `[[hooks.commands]]` tables. See the [Settings Reference](/config/settings-reference/#hooks) for every key.

```toml
[[hooks]]
event = "pre-workspace-activation"
matcher = { bundleId = "com.tinyspeck.slackmacgap" }

[[hooks.commands]]
command = "~/.config/omniwm/hooks/stay-put.sh"
timeoutMs = 200

[[hooks]]
event = "pre-window-admission"
matcher = { bundleId = "com.tinyspeck.slackmacgap", titleRegex = "^Huddle" }

[[hooks.commands]]
command = "~/.config/omniwm/hooks/route-huddle.sh"
timeoutMs = 300

[[hooks]]
event = "pre-command"
matcher = { commandName = "^close-focused-window$" }

[[hooks.commands]]
command = "~/.config/omniwm/hooks/protect.sh"
timeoutMs = 150
onFailure = "deny"

[[hooks]]
event = "post-workspace-change"

[[hooks.commands]]
command = "~/.config/omniwm/hooks/log-switch.sh"
timeoutMs = 2000
```

- `event` names one of the four events. An unknown name rejects the whole file.
- `matcher` is optional. Without it, the hook runs for every occurrence of the event. When you set more than one matcher key, every key must match.
  - `bundleId` matches the app's bundle ID exactly and ignores case.
  - `titleRegex` is a regular expression that can match anywhere in the window title. It uses the same engine as `titleRegex` in `[[appRules]]`.
  - `commandName` is a regular expression that can match anywhere in the command name.
- `command` is a shell command line. OmniWM runs it with `/bin/sh -c`.
- `timeoutMs` defaults to `500`. When the time runs out, OmniWM stops the process and counts the run as a failure.
- `onFailure` is `allow` or `deny` and defaults to `allow`. It decides what a failure means for a blocking hook. Post hooks ignore it.

`pre-workspace-activation` and `pre-window-admission` can match on `bundleId` and `titleRegex`. `pre-command` can match only on `commandName`. `post-workspace-change` supplies nothing to match, so it takes no matcher. A matcher key that the event cannot supply would never match. OmniWM skips that hook and reports it in Diagnostics. It does the same for an invalid regular expression.

`commandName` sees the name you pass to `omniwmctl command`, such as `close-focused-window`. A hotkey reports the name of the `omniwmctl command` that runs the same action, so one matcher covers the hotkey and the CLI. A hotkey whose action has no `omniwmctl command` equivalent, such as the shell toggle and the window-mark actions, still runs the hook and reports the action's title from the Hotkeys settings instead. `omniwmctl workspace` requests report `workspace.` followed by `focus-name`, `move-to-monitor`, or `rename`. `omniwmctl window` requests report `window.` followed by the action name from [Window Actions](/reference/cli/actions/#window-actions), such as `window.close` or `window.move-to-workspace`.

When several entries match, OmniWM runs their commands in file order. The first command that answers anything other than allow decides, and later commands do not run.

## Read the payload on stdin

OmniWM writes one JSON object to the command's stdin and then closes stdin. Keys use snake_case. `hook_event_name` holds the event name.

### pre-workspace-activation

```json
{
  "hook_event_name": "pre-workspace-activation",
  "window": { "id": 4121, "pid": 812, "bundle_id": "com.tinyspeck.slackmacgap", "title": "general" },
  "workspace": { "id": "6B2C1E0A-3D4F-4A51-9C8E-2F7B5D1A9E44", "name": "chat" },
  "active_workspace": { "id": "9F11A2B3-7C4D-4E5F-8A9B-0C1D2E3F4A5B", "name": "meeting" },
  "monitor_id": 1,
  "source": "focusedWindowChanged"
}
```

`window` is the activated window. `workspace` is the workspace that holds it, and `active_workspace` is the workspace on screen now. `source` names the macOS event that OmniWM observed. `window.title` is `null` when OmniWM has no cached title for the window.

### pre-window-admission

```json
{
  "hook_event_name": "pre-window-admission",
  "window": { "id": 4130, "pid": 990, "bundle_id": "com.tinyspeck.slackmacgap", "app_name": "Slack", "title": "Huddle: design", "role": "AXWindow", "subrole": "AXStandardWindow" },
  "proposed": { "workspace": "chat", "float": false },
  "active_workspace": { "id": "9F11A2B3-7C4D-4E5F-8A9B-0C1D2E3F4A5B", "name": "meeting" }
}
```

`proposed` is the placement that `[[appRules]]` chose. `proposed.workspace` is a workspace name or `null`, and `proposed.float` is `true` when the window would float.

### pre-command

```json
{
  "hook_event_name": "pre-command",
  "command": { "name": "close-focused-window", "source": "ipc", "arguments": {} },
  "focused_window": { "id": 4121, "pid": 812, "bundle_id": "com.apple.Terminal", "title": "zsh" },
  "active_workspace": { "id": "9F11A2B3-7C4D-4E5F-8A9B-0C1D2E3F4A5B", "name": "meeting" }
}
```

`command.source` is `ipc` for `omniwmctl`, `hotkey` for a hotkey, or `shell` for a workspace-bar widget. `command.arguments` holds each scalar argument of the request as a string under its snake_case name, so `omniwmctl command focus left` sends `{ "direction": "left" }` and `omniwmctl window close <id>` sends `{ "window_id": "<id>" }`. Arguments that are objects, such as a workspace target, are left out. A hotkey sends an empty object. `focused_window` is the window that has focus when the command arrives. `focused_window.title` is `null` when OmniWM has no cached title for the window.

### post-workspace-change

```json
{
  "hook_event_name": "post-workspace-change",
  "from": { "id": "9F11A2B3-7C4D-4E5F-8A9B-0C1D2E3F4A5B", "name": "meeting" },
  "to": { "id": "6B2C1E0A-3D4F-4A51-9C8E-2F7B5D1A9E44", "name": "chat" },
  "monitor_id": 1
}
```

## Answer with an exit code

| Exit status | Result |
| --- | --- |
| `0` with empty stdout | Allow. OmniWM carries on as if no hook ran. |
| `0` with a JSON object on stdout | On `pre-window-admission`, OmniWM applies the object. On the other blocking events, any output other than whitespace counts as a failure. |
| `2` | Deny. OmniWM uses the trimmed stderr as the reason. Empty stderr gives the reason `denied by <command>`. |
| Any other status | Failure. `onFailure` decides. |

A timeout, a command that cannot launch, and stdout that is not a valid object also count as failures.

The `pre-window-admission` object has two optional keys. `workspace` names the workspace to place the window on. `float` set to `true` floats the window, and `false` tiles it. A key you leave out keeps the value from `proposed`.

```json
{ "workspace": "chat", "float": true }
```

`workspace` is a raw workspace name, the name you see in `omniwmctl query workspaces`. A name that matches no workspace leaves the placement from `proposed` in place.

## Choose how a blocking hook fails

Blocking hooks fail open by default. With `onFailure = "allow"`, a crash, a timeout, or bad output lets the action proceed as if the hook allowed it. Set `onFailure = "deny"` on a protective hook so that a failure blocks the action instead. Post hooks ignore `onFailure`.

## Read a denied command in omniwmctl

When a `pre-command` hook denies an `omniwmctl` request, the CLI prints the reason and exits with status `1`.

```
$ omniwmctl command close-focused-window
error: hook_denied: Terminal is protected
$ echo $?
1
```

JSON output carries the error code `hook_denied` and the text in the response's `reason` field. A denied hotkey does not run its action.

If the focused window, the workspace, or the layout changes while the hook runs, OmniWM does not run the command, even when the hook allows it. `omniwmctl` then reports `workspace_state_conflict`. A protective hook can never approve one window and have the command act on another.

If OmniWM stops while a command waits on a hook, `omniwmctl` reports `ignored_disabled`.

Hooks raise the IPC protocol version. An `omniwmctl` from an earlier build reports `protocol_mismatch`, so use the `omniwmctl` that ships with this build.

## Examples

The scripts read the payload with `jq`, which macOS includes at `/usr/bin/jq`. Make each script executable with `chmod +x`.

### Keep a workspace on screen while an app activates

When Slack activates while the `meeting` workspace is on screen, stay on `meeting`.

```toml
[[hooks]]
event = "pre-workspace-activation"
matcher = { bundleId = "com.tinyspeck.slackmacgap" }

[[hooks.commands]]
command = "~/.config/omniwm/hooks/stay-put.sh"
timeoutMs = 200
```

```sh
#!/bin/sh
active=$(jq -r '.active_workspace.name')
if [ "$active" = "meeting" ]; then
  echo "meeting workspace is pinned" >&2
  exit 2
fi
exit 0
```

### Float a window and route it to a workspace

Float Slack huddle windows and place them on `chat`.

```toml
[[hooks]]
event = "pre-window-admission"
matcher = { bundleId = "com.tinyspeck.slackmacgap" }

[[hooks.commands]]
command = "~/.config/omniwm/hooks/route-huddle.sh"
timeoutMs = 300
```

```sh
#!/bin/sh
title=$(jq -r '.window.title // empty')
case "$title" in
  Huddle*) printf '{"workspace":"chat","float":true}\n' ;;
esac
exit 0
```

### Protect a window from close-focused-window

Refuse to close Terminal windows. `onFailure = "deny"` keeps Terminal protected when the script fails.

```toml
[[hooks]]
event = "pre-command"
matcher = { commandName = "^close-focused-window$" }

[[hooks.commands]]
command = "~/.config/omniwm/hooks/protect.sh"
timeoutMs = 150
onFailure = "deny"
```

```sh
#!/bin/sh
bundle=$(jq -r '.focused_window.bundle_id // empty')
if [ "$bundle" = "com.apple.Terminal" ]; then
  echo "Terminal is protected" >&2
  exit 2
fi
exit 0
```

## Known limits

- `pre-window-admission` runs only for windows created while OmniWM runs, and only when OmniWM would manage the window. A full rescan and rule reevaluation do not run it.
- `post-workspace-change` runs only for the interaction monitor. A workspace switch on another monitor does not run it.
- The command palette does not run `pre-command` hooks.
- While a `pre-workspace-activation` hook runs, the activated window keeps keyboard focus on its hidden workspace. Keep that hook's `timeoutMs` short.
- A denied window stays unmanaged only until the next full rescan. A rescan admits it without running the hook.
