#!/bin/zsh
set -u

STATE_DIR="__HOME__/.cache/airpods-auto"
ROOT_STATE_DIR="/var/db/airpods-auto-heal"
CONFIG_FILE="__HOME__/.config/airpods-auto-heal/config.env"
REQUEST_FILE="$STATE_DIR/privileged.request"
RESULT_FILE="$ROOT_STATE_DIR/privileged.result"
LOG_FILE="$ROOT_STATE_DIR/privileged.log"
DRY_RUN=0
DEBUG=0

load_config() {
  local line
  local key
  local value
  local raw

  trim_spaces() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
  }

  normalize_value() {
    local s
    local first
    local last
    s="$(trim_spaces "$1")"
    if [[ ${#s} -ge 2 ]]; then
      first="${s:0:1}"
      last="${s: -1}"
    else
      first=""
      last=""
    fi
    if [[ "$first" == '"' && "$last" == '"' ]]; then
      s="${s:1:${#s}-2}"
    elif [[ "$first" == "'" && "$last" == "'" ]]; then
      s="${s:1:${#s}-2}"
    fi
    printf '%s' "$s"
  }

  [[ ! -f "$CONFIG_FILE" ]] && return

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw="$(trim_spaces "$line")"
    [[ -z "$raw" || "$raw" == \#* ]] && continue
    raw="${raw#export }"
    key="$(trim_spaces "${raw%%=*}")"
    value="$(normalize_value "${raw#*=}")"
    case "$key" in
      DRY_RUN)
        if [[ "$value" == "1" ]]; then
          DRY_RUN=1
        else
          DRY_RUN=0
        fi
        ;;
      DEBUG)
        if [[ "$value" == "1" ]]; then
          DEBUG=1
        else
          DEBUG=0
        fi
        ;;
    esac
  done <"$CONFIG_FILE"
}

log_msg() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
}

debug_msg() {
  if [[ "$DEBUG" -eq 1 ]]; then
    log_msg "DEBUG: $1"
  fi
}

# Avoid recreating user cache directories as root; watcher should own this path.
if [[ ! -d "$STATE_DIR" ]]; then
  exit 0
fi
mkdir -p "$ROOT_STATE_DIR"
chmod 755 "$ROOT_STATE_DIR" >/dev/null 2>&1 || true

load_config

if [[ ! -f "$REQUEST_FILE" ]]; then
  exit 0
fi

if [[ -L "$REQUEST_FILE" ]]; then
  rm -f "$REQUEST_FILE"
  log_msg "Ignored symlink request file."
  exit 1
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
tmp_result="$ROOT_STATE_DIR/privileged.result.tmp"
{
  echo "last_action=$action"
  echo "last_exit_code=$exit_code"
  echo "last_run_epoch=$now_epoch"
} >"$tmp_result"
chmod 644 "$tmp_result" >/dev/null 2>&1 || true
mv -f "$tmp_result" "$RESULT_FILE"

log_msg "action=$action exit_code=$exit_code dry_run=$DRY_RUN"

exit "$exit_code"
