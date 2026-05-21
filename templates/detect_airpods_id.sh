#!/bin/zsh
set -euo pipefail

BLUEUTIL_BIN=""
CONFIG_DIR="$HOME/.config/airpods-auto-heal"
CONFIG_FILE="$CONFIG_DIR/config.env"
MODE="list"
WRITE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      MODE="list"
      ;;
    --first)
      MODE="first"
      ;;
    --write)
      MODE="write"
      ;;
    --write-id)
      MODE="write-id"
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing ID value for --write-id" >&2
        exit 64
      fi
      WRITE_ID="$1"
      ;;
    *)
      echo "Usage: $0 [--list|--first|--write|--write-id <ID>]" >&2
      exit 64
      ;;
  esac
  shift
done

resolve_blueutil() {
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

  echo "blueutil not found. Install with: brew install blueutil" >&2
  exit 69
}

resolve_blueutil

paired_json="$($BLUEUTIL_BIN --paired --format json 2>/dev/null || echo '[]')"
connected_json="$($BLUEUTIL_BIN --connected --format json 2>/dev/null || echo '[]')"

candidates="$(PAIRED_JSON="$paired_json" CONNECTED_JSON="$connected_json" python3 - <<'PY'
import json
import os
import sys

paired = json.loads(os.environ.get("PAIRED_JSON", "[]") or "[]")
connected = json.loads(os.environ.get("CONNECTED_JSON", "[]") or "[]")

if isinstance(paired, dict):
    paired = [paired]
if isinstance(connected, dict):
    connected = [connected]

connected_set = set()
for d in connected:
    addr = d.get("address") or d.get("id")
    if addr:
        connected_set.add(addr.upper())

rows = []
for d in paired:
    name = (d.get("name") or "").strip()
    addr = (d.get("address") or d.get("id") or "").strip()
    if not addr:
        continue
    lname = name.lower()
    if "airpods" not in lname:
        continue
    is_connected = addr.upper() in connected_set
    score = 0
    if is_connected:
        score += 100
    if "airpods pro" in lname:
        score += 10
    rows.append((score, addr, name, is_connected))

rows.sort(key=lambda r: (-r[0], r[2].lower(), r[1]))
for _, addr, name, is_connected in rows:
    state = "connected" if is_connected else "paired"
    print(f"{addr}\t{name}\t{state}")
PY
)"

if [[ "$MODE" == "list" ]]; then
  if [[ -z "$candidates" ]]; then
    echo "No paired AirPods devices found."
    exit 1
  fi
  echo "$candidates"
  exit 0
fi

first_id="$(printf '%s\n' "$candidates" | awk 'NF {print $1; exit}')"
if [[ -z "$first_id" ]]; then
  echo "No AirPods ID candidates found." >&2
  exit 1
fi

if [[ "$MODE" == "first" ]]; then
  echo "$first_id"
  exit 0
fi

if [[ "$MODE" == "write-id" ]]; then
  first_id="$WRITE_ID"
fi

mkdir -p "$CONFIG_DIR"
if [[ -f "$CONFIG_FILE" ]]; then
  awk -v id="$first_id" '
    BEGIN {done=0}
    /^AIRPODS_ID=/ {print "AIRPODS_ID=" id; done=1; next}
    {print}
    END {if (!done) print "AIRPODS_ID=" id}
  ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
else
  echo "AIRPODS_ID=$first_id" > "$CONFIG_FILE"
fi

echo "Wrote AIRPODS_ID=$first_id to $CONFIG_FILE"
