# AirPods Auto-Heal (macOS)

Installable launchd automation for AirPods stability on Mac:
- keeps audio stable while AirPods are connected
- restores Continuity features after disconnect
- auto-recover on sustained Bluetooth degradation
- sends macOS notifications for connect/disconnect, degradation, requests, and completion status

## What It Installs

- User LaunchAgent: `com.screendead.airpods-auto`
- Root LaunchDaemon: `com.screendead.airpods-auto-privileged`
- User watcher script in `~/Library/Application Support/airpods-auto-heal`
- Root worker script in `/usr/local/libexec/airpods_auto_privileged_worker.sh`

## Requirements

- macOS
- `blueutil` installed (`brew install blueutil`)
- admin rights (one-time, for daemon install)

## Install

```bash
chmod +x install.sh
./install.sh
```

## Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## Configure AirPods Device ID

Edit:

`~/.config/airpods-auto-heal/config.env`

Default:

```bash
AIRPODS_ID=
```

Find current connected Bluetooth devices:

```bash
blueutil --connected
```

Auto-detect likely AirPods IDs:

```bash
~/Library/Application\ Support/airpods-auto-heal/detect_airpods_id.sh --list
```

Write the best detected candidate into config automatically:

```bash
~/Library/Application\ Support/airpods-auto-heal/detect_airpods_id.sh --write
```

## Logs

- `~/.cache/airpods-auto/agent.log`
- `~/.cache/airpods-auto/privileged.log`
- `~/.cache/airpods-auto/agent.err`
- `~/.cache/airpods-auto/privileged.err`

## Manual Service Checks

```bash
launchctl print gui/$(id -u)/com.screendead.airpods-auto | sed -n '1,80p'
sudo launchctl print system/com.screendead.airpods-auto-privileged | sed -n '1,80p'
```

## Notes

- Root daemon may appear as not running between intervals; that is normal.
- The user watcher runs every 15 seconds.
- Privileged worker runs every 5 seconds and processes queued actions.
