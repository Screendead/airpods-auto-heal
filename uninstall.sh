#!/bin/zsh
set -euo pipefail

HOME_DIR="$HOME"
USER_AGENT_LABEL="com.screendead.airpods-auto"
ROOT_DAEMON_LABEL="com.screendead.airpods-auto-privileged"
USER_AGENT_PATH="$HOME_DIR/Library/LaunchAgents/${USER_AGENT_LABEL}.plist"
ROOT_DAEMON_PATH="/Library/LaunchDaemons/${ROOT_DAEMON_LABEL}.plist"
WORKER_PATH="/usr/local/libexec/airpods_auto_privileged_worker.sh"
APP_DIR="$HOME_DIR/Library/Application Support/airpods-auto-heal"

launchctl bootout "gui/$(id -u)" "$USER_AGENT_PATH" >/dev/null 2>&1 || true
rm -f "$USER_AGENT_PATH"

sudo -v
sudo launchctl bootout system "$ROOT_DAEMON_PATH" >/dev/null 2>&1 || true
sudo rm -f "$ROOT_DAEMON_PATH" "$WORKER_PATH"

rm -rf "$APP_DIR"

echo "Uninstalled AirPods Auto-Heal launchd services."
echo "Logs and config retained in ~/.cache/airpods-auto and ~/.config/airpods-auto-heal."
