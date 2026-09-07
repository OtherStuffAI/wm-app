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

# Exercise the real updater and each platform entry point in an isolated repo.
# Native SDKs, signing, Git pulls and app launches must not run in this test.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wmapp-build-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/repo/tools" "$fixture/repo/app/assets/flightdeck" "$fixture/source/dist" "$fixture/bin"
cp "$SCRIPT" "$fixture/repo/tools/"
cp "$REPO_DIR"/build_*.sh "$fixture/repo/"
printf '{}\n' > "$fixture/source/package.json"
printf 'stale\n' > "$fixture/repo/app/assets/flightdeck/stale.txt"
cat > "$fixture/bin/bun" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'run build' ]]
[[ "$PWD" == "$FLIGHT_DECK_DIR" ]]
printf 'flightdeck\n' >> "$BUILD_TEST_LOG"
[[ "${FAIL_FLIGHTDECK:-0}" != 1 ]] || exit 23
printf '{"buildNumber":1888}\n' > dist/version.json
STUB
cat > "$fixture/bin/flutter" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ -f assets/flightdeck/version.json ]]
[[ ! -f assets/flightdeck/stale.txt ]]
[[ "$(head -n 1 "$BUILD_TEST_LOG")" == flightdeck ]]
printf 'flutter %s\n' "$*" >> "$BUILD_TEST_LOG"
# Stop before any post-build launch, artifact or signing inspection.
if [[ "${1:-}" == build ]]; then exit 42; fi
STUB
cat > "$fixture/bin/uname" <<'STUB'
#!/usr/bin/env bash
printf 'Darwin\n'
STUB
cat > "$fixture/bin/git" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
export FLIGHT_DECK_DIR="$fixture/source"
export BUILD_TEST_LOG="$fixture/events"
export WMAPP_ANDROID_KEYSTORE="$fixture/test-keystore"
export WMAPP_ANDROID_STORE_PASSWORD=test-only
export WMAPP_ANDROID_KEY_PASSWORD=test-only
touch "$WMAPP_ANDROID_KEYSTORE"

for script in "$fixture/repo"/build_*.sh; do
  : > "$BUILD_TEST_LOG"
  status=0
  bash "$script" > "$fixture/output" 2>&1 || status=$?
  if [[ "$status" != 42 ]] || ! rg -q '^flutter build ' "$BUILD_TEST_LOG"; then
    cat "$fixture/output" >&2
    printf 'platform build did not refresh Flight Deck first: %s (exit %s)\n' "$script" "$status" >&2
    exit 1
  fi

  : > "$BUILD_TEST_LOG"
  status=0
  FAIL_FLIGHTDECK=1 bash "$script" > "$fixture/output" 2>&1 || status=$?
  if [[ "$status" != 23 ]] || rg -q '^flutter ' "$BUILD_TEST_LOG"; then
    cat "$fixture/output" >&2
    printf 'platform build continued after Flight Deck failed: %s\n' "$script" >&2
    exit 1
  fi
done

# Simulator follows the same preparation path as an iOS device build.
: > "$BUILD_TEST_LOG"
status=0
bash "$fixture/repo/build_ios_debug.sh" simulator > "$fixture/output" 2>&1 || status=$?
[[ "$status" == 42 ]]
rg -q '^flutter build ios --simulator --debug$' "$BUILD_TEST_LOG"

# Manual reuse must not invoke the source build.
: > "$BUILD_TEST_LOG"
"$fixture/repo/tools/update_flightdeck_bundle.sh" --use-existing-dist
[[ ! -s "$BUILD_TEST_LOG" ]]

printf 'All seven platform helpers refresh Flight Deck and stop on build failure; simulator and manual reuse passed\n'
