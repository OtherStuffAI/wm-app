#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$REPO_DIR/tools/update_flightdeck_bundle.sh"

default_source="$("$SCRIPT" --print-source)"
expected_default="$REPO_DIR/../flightdeck"
[[ "$default_source" == "$expected_default" ]] || {
  printf 'expected default source %s, got %s\n' "$expected_default" "$default_source" >&2
  exit 1
}

override_source="/tmp/wmapp-flightdeck-source-override"
actual_override="$(FLIGHT_DECK_DIR="$override_source" "$SCRIPT" --print-source)"
[[ "$actual_override" == "$override_source" ]] || {
  printf 'expected override source %s, got %s\n' "$override_source" "$actual_override" >&2
  exit 1
}

printf 'update_flightdeck_bundle source resolution passed\n'
