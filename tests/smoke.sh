#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

zsh -n install.sh
zsh -n uninstall.sh
zsh -n templates/airpods_auto_watch.sh
zsh -n templates/airpods_auto_privileged_worker.sh
zsh -n templates/detect_airpods_id.sh

./install.sh --help >/dev/null

if ./install.sh --airpods-id invalid-id >/dev/null 2>&1; then
  echo "Expected invalid BT ID validation failure" >&2
  exit 1
fi

echo "Smoke checks passed."
