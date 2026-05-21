#!/bin/zsh
set -u

STATE_DIR="__HOME__/.cache/airpods-auto"
CONFIG_FILE="__HOME__/.config/airpods-auto-heal/config.env"
REQUEST_FILE="$STATE_DIR/privileged.request"
RESULT_FILE="$STATE_DIR/privileged.result"
LOG_FILE="$STATE_DIR/privileged.log"
TARGET_USER="__USER__"
TARGET_GROUP="staff"
DRY_RUN=0
DEBUG=0

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE" 2>/dev/null || true
fi

log_msg() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
}

debug_msg() {
  if [[ "$DEBUG" -eq 1 ]]; then
    log_msg "DEBUG: $1"
  fi
}

if id -gn "$TARGET_USER" >/dev/null 2>&1; then
  TARGET_GROUP="$(id -gn "$TARGET_USER")"
fi

mkdir -p "$STATE_DIR"

if [[ ! -f "$REQUEST_FILE" ]]; then
  exit 0
fi

action="$(head -n 1 "$REQUEST_FILE" 2>/dev/null | tr -d '\r\n')"
rm -f "$REQUEST_FILE"

if [[ -z "$action" ]]; then
  exit 0
fi

debug_msg "Worker received action=$action"

exit_code=0
if [[ "$DRY_RUN" -eq 1 ]]; then
  debug_msg "DRY_RUN enabled; skipping privileged action execution."
else
  case "$action" in
    stable_on)
      /sbin/ifconfig awdl0 down || exit_code=1
      /sbin/ifconfig llw0 down || exit_code=1
      ;;
    continuity_restore)
      /sbin/ifconfig awdl0 up || exit_code=1
      /sbin/ifconfig llw0 up || exit_code=1
      ;;
    recover)
      /sbin/ifconfig awdl0 down || exit_code=1
      /sbin/ifconfig llw0 down || exit_code=1
      /usr/bin/killall coreaudiod >/dev/null 2>&1 || true
      ;;
    *)
      exit_code=64
      ;;
  esac
fi

now_epoch=$(date +%s)
{
  echo "last_action=$action"
  echo "last_exit_code=$exit_code"
  echo "last_run_epoch=$now_epoch"
} >"$RESULT_FILE"

log_msg "action=$action exit_code=$exit_code dry_run=$DRY_RUN"

/usr/sbin/chown "$TARGET_USER:$TARGET_GROUP" "$RESULT_FILE" "$LOG_FILE" >/dev/null 2>&1 || true
chmod 644 "$RESULT_FILE" "$LOG_FILE" >/dev/null 2>&1 || true

exit "$exit_code"
