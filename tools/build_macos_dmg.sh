#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_DIR="$ROOT/app"
DIST_DIR="${WMAPP_DIST_DIR:-$ROOT/dist/macos}"
VERSION="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$APP_DIR/pubspec.yaml")"
APP_PATH="$APP_DIR/build/macos/Build/Products/Release/wingman_app.app"
DMG_PATH="$DIST_DIR/WMApp-$VERSION-macos-universal.dmg"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${MACOS_NOTARY_PROFILE:-}"
ALLOW_AD_HOC=false

if [[ "${1:-}" == "--ad-hoc" ]]; then
  ALLOW_AD_HOC=true
elif [[ -n "${1:-}" ]]; then
  printf 'usage: %s [--ad-hoc]\n' "$0" >&2
  exit 2
fi

for tool in flutter codesign hdiutil spctl shasum; do
  command -v "$tool" >/dev/null 2>&1 || { printf '%s is required.\n' "$tool" >&2; exit 1; }
done

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$SIGN_IDENTITY" && "$ALLOW_AD_HOC" != true ]]; then
  echo 'No Developer ID Application identity is available. Use --ad-hoc only for a clearly labelled local evaluation artifact.' >&2
  exit 1
fi
if [[ -z "$NOTARY_PROFILE" && "$ALLOW_AD_HOC" != true ]]; then
  echo 'MACOS_NOTARY_PROFILE is required for a public release build.' >&2
  exit 1
fi
if [[ -n "$NOTARY_PROFILE" && -z "$SIGN_IDENTITY" ]]; then
  echo 'Notarization is not permitted for an ad-hoc build.' >&2
  exit 1
fi

(cd "$APP_DIR" && flutter build macos --release)
[[ -d "$APP_PATH" ]] || { echo "Missing built app: $APP_PATH" >&2; exit 1; }

if [[ "$ALLOW_AD_HOC" != true ]]; then
  for package in "$APP_PATH"/Contents/Resources/FIPS/*.pkg; do
    if ! pkgutil --check-signature "$package" >/dev/null 2>&1; then
      echo "Bundled FIPS package is unsigned; refusing a public release: $package" >&2
      exit 1
    fi
  done
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --strict --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  codesign --force --deep --strict --sign - "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/wmapp-dmg.XXXXXX")"
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT INT TERM
cp -R "$APP_PATH" "$STAGE/WMApp.app"
ln -s /Applications "$STAGE/Applications"
rm -f -- "$DMG_PATH"
hdiutil create -quiet -volname WMApp -srcfolder "$STAGE" -format UDZO -ov "$DMG_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"
else
  echo 'Notarization skipped: MACOS_NOTARY_PROFILE is not configured.' >&2
fi

shasum -a 256 "$DMG_PATH"
printf '%s\n' "$DMG_PATH"
