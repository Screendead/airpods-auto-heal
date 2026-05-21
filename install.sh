#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME"
USER_NAME="$(id -un)"
APP_DIR="$HOME_DIR/Library/Application Support/airpods-auto-heal"
CACHE_DIR="$HOME_DIR/.cache/airpods-auto"
CONFIG_DIR="$HOME_DIR/.config/airpods-auto-heal"
USER_AGENT_LABEL="com.screendead.airpods-auto"
ROOT_DAEMON_LABEL="com.screendead.airpods-auto-privileged"
USER_AGENT_PATH="$HOME_DIR/Library/LaunchAgents/${USER_AGENT_LABEL}.plist"
ROOT_DAEMON_PATH="/Library/LaunchDaemons/${ROOT_DAEMON_LABEL}.plist"
WORKER_PATH="/usr/local/libexec/airpods_auto_privileged_worker.sh"

render_template() {
  local src="$1"
  local dest="$2"
  sed \
    -e "s|__HOME__|$HOME_DIR|g" \
    -e "s|__USER__|$USER_NAME|g" \
    "$src" > "$dest"
}

mkdir -p "$APP_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$HOME_DIR/Library/LaunchAgents"

render_template "$ROOT_DIR/templates/airpods_auto_watch.sh" "$APP_DIR/airpods_auto_watch.sh"
render_template "$ROOT_DIR/templates/airpods_auto_privileged_worker.sh" "$APP_DIR/airpods_auto_privileged_worker.sh"
install -m 755 "$ROOT_DIR/templates/detect_airpods_id.sh" "$APP_DIR/detect_airpods_id.sh"
render_template "$ROOT_DIR/templates/com.screendead.airpods-auto.plist" "$USER_AGENT_PATH"
render_template "$ROOT_DIR/templates/com.screendead.airpods-auto-privileged.plist" "$APP_DIR/com.screendead.airpods-auto-privileged.plist"

chmod 755 "$APP_DIR/airpods_auto_watch.sh" "$APP_DIR/airpods_auto_privileged_worker.sh"

if [[ ! -f "$CONFIG_DIR/config.env" ]]; then
  {
    echo "AIRPODS_ID="
  } > "$CONFIG_DIR/config.env"
fi

sudo -v
sudo install -d -m 755 /usr/local/libexec
sudo install -m 755 "$APP_DIR/airpods_auto_privileged_worker.sh" "$WORKER_PATH"
sudo install -m 644 "$APP_DIR/com.screendead.airpods-auto-privileged.plist" "$ROOT_DAEMON_PATH"
sudo launchctl bootout system "$ROOT_DAEMON_PATH" >/dev/null 2>&1 || true
sudo launchctl bootstrap system "$ROOT_DAEMON_PATH"
sudo launchctl kickstart -k "system/$ROOT_DAEMON_LABEL"

launchctl bootout "gui/$(id -u)" "$USER_AGENT_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$USER_AGENT_PATH"
launchctl kickstart -k "gui/$(id -u)/$USER_AGENT_LABEL"

echo "Installed AirPods Auto-Heal."
echo "User agent: $USER_AGENT_LABEL"
echo "Root daemon: $ROOT_DAEMON_LABEL"
echo "Config: $CONFIG_DIR/config.env"
echo "Logs: $CACHE_DIR"
