#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <validated-sol-dist> <tree-sha256> [Flutter build ios options]" >&2
  exit 2
fi
DIST="$1"
DIGEST="$2"
shift 2
python3 "$REPO_DIR/tools/ios/package_ambulando.py" "$DIST" --expected-sha256 "$DIGEST"
"$REPO_DIR/tools/ios/build_core.sh"
cd "$REPO_DIR/app"
flutter pub get
flutter build ios --flavor ambulando "$@"
