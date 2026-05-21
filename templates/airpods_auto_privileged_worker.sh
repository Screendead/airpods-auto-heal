#!/bin/zsh
set -u

STATE_DIR="__HOME__/.cache/airpods-auto"
REQUEST_FILE="$STATE_DIR/privileged.request"
RESULT_FILE="$STATE_DIR/privileged.result"
LOG_FILE="$STATE_DIR/privileged.log"
TARGET_USER="__USER__"
TARGET_GROUP="staff"

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

exit_code=0
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

now_epoch=$(date +%s)
{
  echo "last_action=$action"
  echo "last_exit_code=$exit_code"
  echo "last_run_epoch=$now_epoch"
} >"$RESULT_FILE"

printf '%s action=%s exit_code=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$action" "$exit_code" >>"$LOG_FILE"

/usr/sbin/chown "$TARGET_USER:$TARGET_GROUP" "$RESULT_FILE" "$LOG_FILE" >/dev/null 2>&1 || true
chmod 644 "$RESULT_FILE" "$LOG_FILE" >/dev/null 2>&1 || true

exit "$exit_code"
