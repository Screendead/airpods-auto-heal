#!/bin/zsh
set -euo pipefail

PURGE_ROOT_STATE=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--purge-root-state)
			PURGE_ROOT_STATE=1
			;;
		-h|--help)
			cat <<'EOF'
Usage: ./uninstall.sh [--purge-root-state]

Options:
	--purge-root-state   Also remove /var/db/airpods-auto-heal runtime artifacts.
EOF
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			exit 64
			;;
	esac
	shift
done

HOME_DIR="$HOME"
USER_AGENT_LABEL="com.screendead.airpods-auto"
ROOT_DAEMON_LABEL="com.screendead.airpods-auto-privileged"
USER_AGENT_PATH="$HOME_DIR/Library/LaunchAgents/${USER_AGENT_LABEL}.plist"
ROOT_DAEMON_PATH="/Library/LaunchDaemons/${ROOT_DAEMON_LABEL}.plist"
WORKER_PATH="/usr/local/libexec/airpods_auto_privileged_worker.sh"
APP_DIR="$HOME_DIR/Library/Application Support/airpods-auto-heal"
ROOT_STATE_DIR="/var/db/airpods-auto-heal"

launchctl bootout "gui/$(id -u)" "$USER_AGENT_PATH" >/dev/null 2>&1 || true
rm -f "$USER_AGENT_PATH"

sudo -v
sudo launchctl bootout system "$ROOT_DAEMON_PATH" >/dev/null 2>&1 || true
sudo rm -f "$ROOT_DAEMON_PATH" "$WORKER_PATH"

if [[ "$PURGE_ROOT_STATE" -eq 1 ]]; then
	sudo rm -rf "$ROOT_STATE_DIR"
fi

rm -rf "$APP_DIR"

echo "Uninstalled AirPods Auto-Heal launchd services."
if [[ "$PURGE_ROOT_STATE" -eq 1 ]]; then
	echo "Removed root runtime artifacts from $ROOT_STATE_DIR."
else
	echo "Root runtime artifacts retained in $ROOT_STATE_DIR (use --purge-root-state to remove)."
fi
echo "User logs and config retained in ~/.cache/airpods-auto and ~/.config/airpods-auto-heal."
