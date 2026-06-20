<div align="center">

# 🔔 mac-notify

**A macOS menu bar notification queue.**

*Send messages from anywhere. See them at a glance.*

</div>

A lightweight CLI that puts notification messages in your macOS menu bar. Messages queue up with a badge count, and you can dismiss them individually or all at once. Optionally triggers native macOS notification banners too.

- **Simple CLI** — `mac-notify send "deploy finished"` and it's in your menu bar
- **Message queue** — multiple messages stack up with a count badge
- **Click to dismiss** — click any message in the dropdown to remove it
- **Upsert by ID** — update an existing message in-place with `--id`
- **Source tagging** — `--source ci` to know where it came from
- **Overlay popup** — floating panel with pulsing cyan glow, auto-dismisses after 5s
- **Blocker mode** — `--blocker` pins a persistent red-glow panel to the right edge that stays until you click its ✕
- **Menu bar flash** — message text appears in the menu bar for 2s on each send
- **Native notifications** — macOS banner alerts with sound (configurable)
- **Daemon auto-start** — installs as a launchd service, runs on login

---

## Install

Requires Go 1.21+ and macOS.

```sh
git clone https://github.com/shadowfax92/mac-notify
cd mac-notify
mkdir -p ~/go/bin # in case user has not installed go binaries previously
make install
```

This builds the binary, creates an `.app` bundle at `~/Applications/mac-notify.app`, installs the launchd daemon, and symlinks the CLI to your `$GOPATH/bin`.

## Uninstall

```sh
make uninstall
```

## Quick Start

```sh
mac-notify send "hello world"
mac-notify send "build passed" --source ci
mac-notify send "deploying v2" --source deploy --id deploy-status
mac-notify send "$MESSAGE"
mac-notify list
mac-notify clear
```

## Commands

```sh
mac-notify send [message]      # send a notification
mac-notify send "msg" --source ci   # tag with source
mac-notify send "msg" --id build    # upsert by ID
mac-notify send "msg" --blocker     # persistent red blocker (dismiss with ✕)
mac-notify list                # show current messages
mac-notify clear               # clear all messages
mac-notify status              # check if daemon is running
mac-notify install             # install launchd service
mac-notify uninstall           # remove launchd service and stop daemon
mac-notify daemon              # run daemon in foreground (for debugging)
```

### Flags

| Flag | Command | Description |
|------|---------|-------------|
| `--source` | `send` | Origin label (e.g. `ci`, `build`, `deploy`) |
| `--id` | `send` | Message ID for upsert — replaces existing message with same ID |
| `--blocker` | `send` | Show a persistent red-glow panel on the right edge until dismissed with ✕ |

## Menu Bar

The menu bar icon shows 🔔 when empty and 🔔 N when messages are queued.

Click to open the dropdown:

```
🔔 2
├─ [ci] build passed
├─ [deploy] deploying v2
├─ ──────────
└─ Clear All
```

Click a message to dismiss it. Click **Clear All** to reset.

## Overlay Popup

<p align="center">
  <img src="assets/overlay.png" alt="overlay notification" width="400" />
</p>

Each `send` shows a floating dark panel just below the menu bar with a pulsing cyan glow border. It fades in, glows for 5 seconds, and fades out. New messages replace the current overlay.

## Blocker Mode

```sh
mac-notify send --blocker "Deploy is frozen — resolve the conflict before continuing"
```

For things that must not scroll away, `--blocker` shows a **persistent** panel pinned to the **right edge** of the screen with a pulsing **red** glow. Unlike the overlay it never auto-dismisses — it stays until you click the **✕** in its corner. A new `--blocker` send replaces the current one, and `mac-notify clear` dismisses it too.

The send is otherwise normal: it still queues in the menu bar list and (when enabled) fires a system notification. `--blocker` just swaps the transient overlay for the persistent red panel, and is shown even if `overlay_notifications` is disabled.

## Menu Bar Flash

On each `send`, the menu bar temporarily shows the message text (e.g. `🔔 [ci] build passed`) for 2 seconds, then reverts to the badge count.

## Native Notifications

When enabled, each `send` also triggers a macOS notification banner with sound. The app appears in **System Settings → Notifications** as `mac-notify` with its own icon.

## Config

`~/.config/mac-notify/config.yaml`:

```yaml
system_notifications: true
overlay_notifications: true
menu_flash: true
overlay_timeout: 5
```

| Key | Default | Description |
|-----|---------|-------------|
| `system_notifications` | `true` | Show native macOS notification banners |
| `overlay_notifications` | `true` | Show floating overlay popup with glow |
| `menu_flash` | `true` | Flash message text in menu bar for 2s |
| `overlay_timeout` | `5` | Overlay auto-dismiss timeout in seconds |

### Send Formatting

`mac-notify send` can derive the final message, source, and id from config before it talks to the daemon. This is useful when you want to call `mac-notify send "$MESSAGE"` directly from scripts or other tools and let `mac-notify` fill in the rest.

```yaml
system_notifications: true
overlay_notifications: true
menu_flash: true
overlay_timeout: 5
send:
  source: "$DIR_NAME"
  id: "$GIT_BRANCH_NAME"
```

The `send` section supports:

| Key | Description |
|-----|-------------|
| `message` | Override the final message using shell-style `$VAR` / `${VAR}` expansion |
| `source` | Override the final source label using shell-style expansion |
| `id` | Override the final upsert id using shell-style expansion |
| `context_command` | Optional shell command that runs before expansion and prints extra `KEY=VALUE` lines |

Available variables:

| Variable | Description |
|----------|-------------|
| `MESSAGE` | Raw message passed to `mac-notify send` |
| `SOURCE` | Raw `--source` flag value |
| `ID` | Raw `--id` flag value |
| `CWD` | Current working directory |
| `DIR_NAME` | Basename of `CWD` |
| `GIT_BRANCH_NAME` | Current git branch, if `CWD` is inside a git repo |
| any existing environment variable | Passed through automatically |

Missing variables expand to an empty string.

### `context_command`

If you need values that are not already in your environment, set `send.context_command`. It runs through `/bin/sh -c ...` before the final expansion step and receives the current environment plus the built-in variables above.

Each non-empty stdout line must be `KEY=VALUE`. Those values are merged into the context and can then be used in `send.message`, `send.source`, and `send.id`.

Example: tmux-aware notifications without wrapping `mac-notify` in another script:

```yaml
send:
  message: "$MESSAGE"
  source: "$TMUX_SESSION_NAME:$TMUX_WINDOW_NAME"
  id: "$TMUX_SESSION_NAME:$TMUX_WINDOW_NAME"
  context_command: |
    tmux display-message -p 'TMUX_SESSION_NAME=#{session_name}
    TMUX_WINDOW_NAME=#{window_name}
    TMUX_PANE_NAME=#{pane_title}' 2>/dev/null || true
```

Example: use git and directory context for direct forwarding:

```yaml
send:
  source: "$DIR_NAME"
  id: "$DIR_NAME:$GIT_BRANCH_NAME"
```

## Architecture

```
mac-notify send "msg"  ──→  Unix socket IPC  ──→  daemon (menu bar app)
                            ~/.mac-notify.sock       ├─ menuet menu bar
                                                     ├─ overlay popup (NSPanel + glow)
                                                     └─ UNUserNotificationCenter
```

The daemon runs as a `.app` bundle (required for macOS notification permissions) with `LSUIElement=true` to stay out of the Dock. A LaunchAgent keeps it alive and starts it on login.

---

> Personal tool built for my own workflow. Feel free to fork and adapt.
