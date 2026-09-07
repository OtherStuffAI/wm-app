#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APP_DIR="$REPO_DIR/app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS archives require macOS and Xcode." >&2
  exit 1
fi
command -v flutter >/dev/null 2>&1 || {
  echo "flutter is required." >&2
  exit 1
}

"$REPO_DIR/tools/update_flightdeck_bundle.sh"

# Flutter can exit successfully after archiving even when IPA export fails.
# Use a timestamp marker so a stale IPA cannot be reported as this build.
mkdir -p "$APP_DIR/build/ios"
MARKER="$(mktemp "$APP_DIR/build/ios/.testflight-build.XXXXXX")"
trap 'rm -f "$MARKER"' EXIT
(
  cd "$APP_DIR"
  flutter build ipa --release \
    --export-options-plist="$REPO_DIR/docs/deploy/TestFlightExportOptions.plist"
)
IPA="$(find "$APP_DIR/build/ios/ipa" -maxdepth 1 -name '*.ipa' -newer "$MARKER" -print -quit 2>/dev/null || true)"
if [[ -z "$IPA" ]]; then
  echo "No new TestFlight IPA was exported. Inspect the signing errors above." >&2
  echo "Any archive in $APP_DIR/build/ios/archive still requires distribution export." >&2
  exit 1
fi
echo "Exported IPA: $IPA"
echo "Local export only. Upload and verify App Store Connect processing before reporting TestFlight availability."
