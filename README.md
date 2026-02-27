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
- **Native notifications** — macOS banner alerts with sound (configurable)
- **Daemon auto-start** — installs as a launchd service, runs on login

---

## Install

Requires Go 1.21+ and macOS.

```sh
git clone https://github.com/nickhudkins/mac-notify
cd mac-notify
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
mac-notify list
mac-notify clear
```

## Commands

```sh
mac-notify send [message]      # send a notification
mac-notify send "msg" --source ci   # tag with source
mac-notify send "msg" --id build    # upsert by ID
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

## Native Notifications

When enabled, each `send` also triggers a macOS notification banner with sound. The app appears in **System Settings → Notifications** as `mac-notify` with its own icon.

## Config

`~/.config/mac-notify/config.yaml`:

```yaml
system_notifications: true
```

| Key | Default | Description |
|-----|---------|-------------|
| `system_notifications` | `true` | Show native macOS notification banners |

## Architecture

```
mac-notify send "msg"  ──→  Unix socket IPC  ──→  daemon (menu bar app)
                            ~/.mac-notify.sock       ├─ menuet menu bar
                                                     └─ UNUserNotificationCenter
```

The daemon runs as a `.app` bundle (required for macOS notification permissions) with `LSUIElement=true` to stay out of the Dock. A LaunchAgent keeps it alive and starts it on login.

---

> Personal tool built for my own workflow. Feel free to fork and adapt.
