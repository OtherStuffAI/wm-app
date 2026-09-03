#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FLIGHT_DECK_DIR="${FLIGHT_DECK_DIR:-$REPO_DIR/../flightdeck}"
TARGET_DIR="$REPO_DIR/app/assets/flightdeck"
USE_EXISTING_DIST=false

if [[ "${1:-}" == "--print-source" ]]; then
  printf '%s\n' "$FLIGHT_DECK_DIR"
  exit 0
fi

if [[ "${1:-}" == "--use-existing-dist" ]]; then
  USE_EXISTING_DIST=true
elif [[ -n "${1:-}" ]]; then
  printf 'usage: %s [--print-source|--use-existing-dist]\n' "$0" >&2
  exit 2
fi

if [[ "$USE_EXISTING_DIST" == false ]]; then
  (
    cd "$FLIGHT_DECK_DIR"
    bun run build
  )
fi

[[ -f "$FLIGHT_DECK_DIR/dist/version.json" ]] || {
  printf 'missing Flight Deck dist/version.json in %s\n' "$FLIGHT_DECK_DIR" >&2
  exit 1
}

mkdir -p "$TARGET_DIR"
rsync -a --delete "$FLIGHT_DECK_DIR/dist/" "$TARGET_DIR/"

echo "Bundled Flight Deck from $FLIGHT_DECK_DIR/dist"
echo "  $TARGET_DIR"
