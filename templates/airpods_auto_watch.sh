#!/bin/zsh
set -u

AIRPODS_ID_DEFAULT="30:7A:D2:8E:97:C4"
RESTORE_DELAY_SECONDS=90
RESTORE_REQUEST_COOLDOWN_SECONDS=300
REQUEST_MIN_INTERVAL_SECONDS=20
DEGRADE_NOTIFY_COOLDOWN_SECONDS=180
STATE_DIR="__HOME__/.cache/airpods-auto"
CONFIG_DIR="__HOME__/.config/airpods-auto-heal"
CONFIG_FILE="$CONFIG_DIR/config.env"
STATE_FILE="$STATE_DIR/state.env"
LOG_FILE="$STATE_DIR/agent.log"
REQUEST_FILE="$STATE_DIR/privileged.request"
RESULT_FILE="$STATE_DIR/privileged.result"
BLUEUTIL_BIN=""

mkdir -p "$STATE_DIR" "$CONFIG_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
  {
    echo "AIRPODS_ID=$AIRPODS_ID_DEFAULT"
  } >"$CONFIG_FILE"
fi

AIRPODS_ID="$AIRPODS_ID_DEFAULT"
source "$CONFIG_FILE" 2>/dev/null || true

log_msg() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
}

request_privileged() {
  local action="$1"
  local note="$2"
  local pending=""

  if [[ -f "$REQUEST_FILE" ]]; then
    pending="$(head -n 1 "$REQUEST_FILE" 2>/dev/null | tr -d '\\r\\n')"
  fi

  if [[ "$pending" == "$action" ]]; then
    return 0
  fi

  if [[ "$last_request_action" == "$action" && $((now_epoch - last_request_epoch)) -lt "$REQUEST_MIN_INTERVAL_SECONDS" ]]; then
    return 0
  fi

  printf '%s\n' "$action" >"$REQUEST_FILE"
  chmod 666 "$REQUEST_FILE" >/dev/null 2>&1 || true
  last_request_action="$action"
  last_request_epoch=$now_epoch
  log_msg "$note"
}

save_state() {
  {
    echo "streak=$streak"
    echo "last_recover_epoch=$last_recover_epoch"
    echo "disconnected_since_epoch=$disconnected_since_epoch"
    echo "restore_done=$restore_done"
    echo "last_restore_attempt_epoch=$last_restore_attempt_epoch"
    echo "prev_connected=$prev_connected"
    echo "last_request_epoch=$last_request_epoch"
    echo "last_request_action=$last_request_action"
    echo "last_seen_result_epoch=$last_seen_result_epoch"
    echo "degrade_alert_active=$degrade_alert_active"
    echo "last_degrade_notify_epoch=$last_degrade_notify_epoch"
  } >"$STATE_FILE"
}

notify_completion_if_any() {
  local result_action=""
  local result_exit_code=""
  local result_epoch=0
  local action_label=""

  if [[ ! -f "$RESULT_FILE" ]]; then
    return
  fi

  result_action="$(awk -F= '/^last_action=/{print $2}' "$RESULT_FILE" 2>/dev/null)"
  result_exit_code="$(awk -F= '/^last_exit_code=/{print $2}' "$RESULT_FILE" 2>/dev/null)"
  result_epoch="$(awk -F= '/^last_run_epoch=/{print $2}' "$RESULT_FILE" 2>/dev/null)"

  if [[ -z "$result_epoch" ]]; then
    return
  fi
  if [[ "$result_epoch" -le "$last_seen_result_epoch" ]]; then
    return
  fi

  case "$result_action" in
    stable_on) action_label="Stable mode" ;;
    continuity_restore) action_label="Continuity restore" ;;
    recover) action_label="Auto-recover" ;;
    *) action_label="Privileged action" ;;
  esac

  if [[ "$result_exit_code" == "0" ]]; then
    /usr/bin/osascript -e "display notification \"Completed\" with title \"AirPods Auto-Heal\" subtitle \"${action_label}\"" >/dev/null 2>&1 || true
    log_msg "Completion: ${result_action} succeeded."
  else
    /usr/bin/osascript -e "display notification \"Failed (exit ${result_exit_code})\" with title \"AirPods Auto-Heal\" subtitle \"${action_label}\"" >/dev/null 2>&1 || true
    log_msg "Completion: ${result_action} failed with exit ${result_exit_code}."
  fi

  last_seen_result_epoch=$result_epoch
}

resolve_blueutil() {
  if [[ -n "$BLUEUTIL_BIN" ]]; then
    return
  fi

  if command -v blueutil >/dev/null 2>&1; then
    BLUEUTIL_BIN="$(command -v blueutil)"
    return
  fi
  if [[ -x "/opt/homebrew/bin/blueutil" ]]; then
    BLUEUTIL_BIN="/opt/homebrew/bin/blueutil"
    return
  fi
  if [[ -x "/usr/local/bin/blueutil" ]]; then
    BLUEUTIL_BIN="/usr/local/bin/blueutil"
    return
  fi
}

connected=0
resolve_blueutil
if [[ -n "$BLUEUTIL_BIN" ]]; then
  if [[ "$("$BLUEUTIL_BIN" --is-connected "$AIRPODS_ID" 2>/dev/null)" == "1" ]]; then
    connected=1
  fi
elif [[ ! -f "$STATE_DIR/.blueutil_missing_logged" ]]; then
  log_msg "blueutil not found in launchd environment; connection detection unavailable."
  : >"$STATE_DIR/.blueutil_missing_logged"
fi

streak=0
last_recover_epoch=0
disconnected_since_epoch=0
restore_done=0
last_restore_attempt_epoch=0
prev_connected=-1
last_request_epoch=0
last_request_action=""
last_seen_result_epoch=0
degrade_alert_active=0
last_degrade_notify_epoch=0
if [[ -f "$STATE_FILE" ]]; then
  source "$STATE_FILE" 2>/dev/null || true
fi

now_epoch=$(date +%s)
notify_completion_if_any

if [[ "$prev_connected" -ne "$connected" ]]; then
  if [[ "$connected" -eq 1 ]]; then
    /usr/bin/osascript -e 'display notification "AirPods connected" with title "AirPods Auto-Heal"' >/dev/null 2>&1 || true
    log_msg "AirPods connection event: connected."
  elif [[ "$prev_connected" -ne -1 ]]; then
    /usr/bin/osascript -e 'display notification "AirPods disconnected" with title "AirPods Auto-Heal"' >/dev/null 2>&1 || true
    log_msg "AirPods connection event: disconnected."
  fi
fi
prev_connected=$connected

awdl_up=0
llw_up=0
if ifconfig awdl0 2>/dev/null | grep -q '<UP'; then
  awdl_up=1
fi
if ifconfig llw0 2>/dev/null | grep -q '<UP'; then
  llw_up=1
fi

if [[ "$connected" -ne 1 ]]; then
  streak=0

  if [[ "$disconnected_since_epoch" -le 0 ]]; then
    disconnected_since_epoch=$now_epoch
    restore_done=0
  fi

  if [[ "$restore_done" -eq 0 && $((now_epoch - disconnected_since_epoch)) -ge "$RESTORE_DELAY_SECONDS" ]]; then
    if [[ "$awdl_up" -eq 0 || "$llw_up" -eq 0 ]]; then
      if [[ $((now_epoch - last_restore_attempt_epoch)) -ge "$RESTORE_REQUEST_COOLDOWN_SECONDS" ]]; then
        last_restore_attempt_epoch=$now_epoch
        request_privileged "continuity_restore" "Requested continuity restore after disconnect (awdl0/llw0 up)."
        restore_done=1
        /usr/bin/osascript -e 'display notification "Continuity restore requested" with title "AirPods Auto-Heal" subtitle "Applying awdl0/llw0 up"' >/dev/null 2>&1 || true
      fi
    else
      restore_done=1
    fi
  fi

  save_state
  exit 0
fi

disconnected_since_epoch=0
restore_done=0
last_restore_attempt_epoch=0

if [[ "$awdl_up" -eq 1 || "$llw_up" -eq 1 ]]; then
  request_privileged "stable_on" "Requested stable mode enforcement (awdl0/llw0 down)."
  /usr/bin/osascript -e 'display notification "Stable mode requested" with title "AirPods Auto-Heal" subtitle "Applying awdl0/llw0 down"' >/dev/null 2>&1 || true
fi

bt_lines="$(log show --last 30s --style compact --predicate 'process == "bluetoothd"' 2>/dev/null | grep -Ei 'A2DP packet flushed|A2DP LinkQualityReport|NoSync|ReTx')"

flush_count="$(printf '%s\n' "$bt_lines" | grep -ci 'A2DP packet flushed')"
retx_max="$(printf '%s\n' "$bt_lines" | awk '
  /ReTx =/ {
    s=$0; sub(/.*ReTx = */, "", s); sub(/%.*/, "", s); v=s+0;
    if (v>mx) mx=v
  }
  END { if (mx=="") mx=0; printf "%.1f", mx }
')"
nosync_max="$(printf '%s\n' "$bt_lines" | awk '
  /NoSync =/ {
    s=$0; sub(/.*NoSync = */, "", s); sub(/,.*/, "", s); v=s+0;
    if (v>mx) mx=v
  }
  END { if (mx=="") mx=0; print mx }
')"

severe=0
if awk -v r="$retx_max" -v f="$flush_count" -v n="$nosync_max" 'BEGIN {exit !((r+0)>=80 || (f+0)>=20 || (n+0)>=100)}'; then
  severe=1
fi

if [[ "$severe" -eq 1 ]]; then
  streak=$((streak + 1))

  if [[ "$degrade_alert_active" -eq 0 && $((now_epoch - last_degrade_notify_epoch)) -ge "$DEGRADE_NOTIFY_COOLDOWN_SECONDS" ]]; then
    /usr/bin/osascript -e "display notification \"ReTx ${retx_max}%, flush ${flush_count}, NoSync ${nosync_max}\" with title \"AirPods audio degradation detected\"" >/dev/null 2>&1 || true
    log_msg "Degradation detected (retx_max=$retx_max flush=$flush_count nosync=$nosync_max)."
    degrade_alert_active=1
    last_degrade_notify_epoch=$now_epoch
  fi
else
  streak=0
  degrade_alert_active=0
fi

can_recover=0
if [[ "$streak" -ge 3 && $((now_epoch - last_recover_epoch)) -ge 600 ]]; then
  can_recover=1
fi

if [[ "$can_recover" -eq 1 ]]; then
  if [[ -n "$BLUEUTIL_BIN" ]]; then
    "$BLUEUTIL_BIN" --connect "$AIRPODS_ID" >/dev/null 2>&1 || true
  fi
  request_privileged "recover" "Requested auto-recover (retx_max=$retx_max flush=$flush_count nosync=$nosync_max)."
  last_recover_epoch=$now_epoch
  streak=0
  /usr/bin/osascript -e 'display notification "Auto-recover requested" with title "AirPods Auto-Heal" subtitle "Detected sustained audio degradation"' >/dev/null 2>&1 || true
fi

save_state
