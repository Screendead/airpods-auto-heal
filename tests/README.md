# Smoke Tests

This directory contains lightweight checks intended to catch basic regressions quickly.

## Current coverage

- shell syntax checks for installer/runtime scripts
- installer `--help` smoke
- installer invalid `--airpods-id` rejection

## Not covered

- real macOS launchd behavior (`launchctl` execution)
- Bluetooth runtime behavior (`blueutil`, `log show` parsing)
- privileged daemon action execution against live interfaces

CI runs `tests/smoke.sh` as a fast baseline, not as full runtime integration testing.
