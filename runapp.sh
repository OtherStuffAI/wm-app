#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APP_DIR="$REPO_DIR/app"
APP_BUNDLE="$APP_DIR/build/macos/Build/Products/Debug/wingman_app.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/wingman_app"
LOG_FILE="${TMPDIR:-/tmp}/wingman_app.log"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "runapp.sh currently launches the macOS Flutter build only." >&2
  exit 1
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "No built macOS app found at:" >&2
  echo "  $APP_BUNDLE" >&2
  echo >&2
  echo "Run ./build_runapp.sh first." >&2
  exit 1
fi

echo "Starting Wingman app..."
echo "Repo: $REPO_DIR"
echo "Log:  $LOG_FILE"

(
  cd "$APP_DIR"
  export WMAPP_REPO_DIR="$REPO_DIR"
  nohup "$APP_EXECUTABLE" >>"$LOG_FILE" 2>&1 &
)

echo "Launched."
