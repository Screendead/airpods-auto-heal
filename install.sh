#!/bin/zsh
set -euo pipefail

NON_INTERACTIVE=0
AIRPODS_ID_OVERRIDE=""
DRY_RUN_MODE=""
DEBUG_MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive)
      NON_INTERACTIVE=1
      ;;
    --airpods-id)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing value for --airpods-id" >&2
        exit 64
      fi
      AIRPODS_ID_OVERRIDE="$1"
      ;;
    --dry-run)
      DRY_RUN_MODE=1
      ;;
    --debug)
      DEBUG_MODE=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./install.sh [--non-interactive] [--airpods-id <BT_MAC>] [--dry-run] [--debug]

Options:
  --non-interactive      Avoid prompts; first detected candidate is used.
  --airpods-id <BT_MAC>  Force a specific AirPods Bluetooth MAC/ID.
  --dry-run              Do not execute privileged recover actions.
  --debug                Increase logging verbosity.
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

is_valid_bt_id() {
  local id="$1"
  [[ "$id" =~ ^([[:xdigit:]]{2}[:-]){5}[[:xdigit:]]{2}$ ]]
}

mkdir -p "$APP_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$HOME_DIR/Library/LaunchAgents"
chmod 700 "$CACHE_DIR" "$CONFIG_DIR" >/dev/null 2>&1 || true

render_template "$ROOT_DIR/templates/airpods_auto_watch.sh" "$APP_DIR/airpods_auto_watch.sh"
render_template "$ROOT_DIR/templates/airpods_auto_privileged_worker.sh" "$APP_DIR/airpods_auto_privileged_worker.sh"
install -m 755 "$ROOT_DIR/templates/detect_airpods_id.sh" "$APP_DIR/detect_airpods_id.sh"
render_template "$ROOT_DIR/templates/com.screendead.airpods-auto.plist" "$USER_AGENT_PATH"
render_template "$ROOT_DIR/templates/com.screendead.airpods-auto-privileged.plist" "$APP_DIR/com.screendead.airpods-auto-privileged.plist"

chmod 755 "$APP_DIR/airpods_auto_watch.sh" "$APP_DIR/airpods_auto_privileged_worker.sh"

if [[ ! -f "$CONFIG_DIR/config.env" ]]; then
  {
    echo "AIRPODS_ID="
    echo "DRY_RUN=0"
    echo "DEBUG=0"
  } > "$CONFIG_DIR/config.env"
fi
chmod 600 "$CONFIG_DIR/config.env" >/dev/null 2>&1 || true

if [[ -n "$DRY_RUN_MODE" || -n "$DEBUG_MODE" ]]; then
  awk -v dry_run="$DRY_RUN_MODE" -v debug="$DEBUG_MODE" '
    BEGIN {seen_dry=0; seen_debug=0}
    /^DRY_RUN=/ {
      if (dry_run != "") print "DRY_RUN=" dry_run
      else print $0
      seen_dry=1
      next
    }
    /^DEBUG=/ {
      if (debug != "") print "DEBUG=" debug
      else print $0
      seen_debug=1
      next
    }
    {print}
    END {
      if (!seen_dry) print "DRY_RUN=" (dry_run == "" ? "0" : dry_run)
      if (!seen_debug) print "DEBUG=" (debug == "" ? "0" : debug)
    }
  ' "$CONFIG_DIR/config.env" > "$CONFIG_DIR/config.env.tmp"
  mv "$CONFIG_DIR/config.env.tmp" "$CONFIG_DIR/config.env"
  chmod 600 "$CONFIG_DIR/config.env" >/dev/null 2>&1 || true
fi

if [[ -n "$AIRPODS_ID_OVERRIDE" ]]; then
  if ! is_valid_bt_id "$AIRPODS_ID_OVERRIDE"; then
    echo "Invalid Bluetooth ID format for --airpods-id: $AIRPODS_ID_OVERRIDE" >&2
    exit 64
  fi
  "$APP_DIR/detect_airpods_id.sh" --write-id "$AIRPODS_ID_OVERRIDE" >/dev/null
  echo "Configured AIRPODS_ID from --airpods-id: $AIRPODS_ID_OVERRIDE"
fi

current_airpods_id="$(awk -F= '/^AIRPODS_ID=/{print $2}' "$CONFIG_DIR/config.env" 2>/dev/null | tail -n 1)"
if [[ -z "$current_airpods_id" ]]; then
  echo "AIRPODS_ID is empty; attempting auto-detection..."
  candidates="$("$APP_DIR/detect_airpods_id.sh" --list 2>/dev/null || true)"
  candidate_count="$(printf '%s\n' "$candidates" | awk 'NF{c++} END{print c+0}')"

  if [[ "$candidate_count" -eq 1 ]]; then
    selected_id="$(printf '%s\n' "$candidates" | awk 'NF{print $1; exit}')"
    if ! is_valid_bt_id "$selected_id"; then
      echo "Detected AirPods ID has invalid format: $selected_id" >&2
      exit 64
    fi
    "$APP_DIR/detect_airpods_id.sh" --write-id "$selected_id" >/dev/null
    echo "Auto-selected AIRPODS_ID: $selected_id"
  elif [[ "$candidate_count" -gt 1 ]]; then
    echo "Multiple AirPods candidates found:"
    printf '%s\n' "$candidates" | nl -w2 -s'. '

    selected_id=""
    if [[ "$NON_INTERACTIVE" -eq 0 && -t 0 ]]; then
      printf "Choose device number [1-%s] (Enter for 1): " "$candidate_count"
      read -r choice
      if [[ -z "$choice" ]]; then
        choice=1
      fi
      selected_id="$(printf '%s\n' "$candidates" | awk -v n="$choice" 'NF{c++; if (c==n){print $1; exit}}')"
    else
      echo "Non-interactive mode: selecting first candidate automatically."
    fi

    if [[ -z "$selected_id" ]]; then
      selected_id="$(printf '%s\n' "$candidates" | awk 'NF{print $1; exit}')"
      echo "No valid selection; defaulting to first candidate: $selected_id"
    fi

    if ! is_valid_bt_id "$selected_id"; then
      echo "Selected AirPods ID has invalid format: $selected_id" >&2
      exit 64
    fi

    "$APP_DIR/detect_airpods_id.sh" --write-id "$selected_id" >/dev/null
    echo "Configured AIRPODS_ID: $selected_id"
  else
    echo "No AirPods candidates found. Set AIRPODS_ID manually in $CONFIG_DIR/config.env"
  fi
fi

sudo -v
sudo install -d -m 755 /usr/local/libexec
sudo install -d -m 755 /var/db/airpods-auto-heal
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
echo "User logs: $CACHE_DIR"
echo "Root logs/state: /var/db/airpods-auto-heal"
