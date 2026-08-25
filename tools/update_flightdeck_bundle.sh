#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FLIGHT_DECK_DIR="${FLIGHT_DECK_DIR:-$REPO_DIR/../flightdeck}"
TARGET_DIR="$REPO_DIR/app/assets/flightdeck"

if [[ "${1:-}" == "--print-source" ]]; then
  printf '%s\n' "$FLIGHT_DECK_DIR"
  exit 0
fi

(
  cd "$FLIGHT_DECK_DIR"
  bun run build
)

mkdir -p "$TARGET_DIR"
rsync -a --delete "$FLIGHT_DECK_DIR/dist/" "$TARGET_DIR/"

echo "Bundled Flight Deck from $FLIGHT_DECK_DIR/dist"
echo "  $TARGET_DIR"
