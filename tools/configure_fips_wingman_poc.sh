#!/bin/sh
set -eu

CONFIG="${FIPS_CONFIG_PATH:-/usr/local/etc/fips/fips.yaml}"
PLIST="${FIPS_LAUNCHD_PLIST:-/Library/LaunchDaemons/com.fips.daemon.plist}"

if [ ! -f "$CONFIG" ]; then
  echo "FIPS config was not installed at $CONFIG" >&2
  exit 1
fi

BACKUP="${CONFIG}.pre-wingman-poc"
if [ ! -f "$BACKUP" ]; then
  cp -p "$CONFIG" "$BACKUP"
fi
TEMP="${CONFIG}.wingman-poc.tmp.$$"
trap 'rm -f "$TEMP"' EXIT
cp -p "$CONFIG" "$TEMP"

# FIPS v0.5.0 ships each of these settings as a commented default. Replace
# active values too, but never touch node.identity.nsec, key files, peers, or
# unrelated operator configuration.
sed -E -i '' \
  -e 's/^    (#[[:space:]]*)?persistent:[[:space:]]*(true|false)$/    persistent: true/' \
  -e '/^    (#[[:space:]]*)?nostr:$/,/^    (#[[:space:]]*)?lan:$/ {' \
  -e 's/^    (#[[:space:]]*)?nostr:$/    nostr:/' \
  -e 's/^    (#[[:space:]]*)?enabled:[[:space:]]*(true|false)$/      enabled: true/' \
  -e 's/^      enabled:[[:space:]]*(true|false)$/      enabled: true/' \
  -e 's/^    (#[[:space:]]*)?policy:[[:space:]]*[^#]+([[:space:]]*#.*)?$/      policy: open/' \
  -e 's/^      policy:[[:space:]]*[^#]+([[:space:]]*#.*)?$/      policy: open/' \
  -e 's/^    (#[[:space:]]*)?app:[[:space:]]*[^#]+([[:space:]]*#.*)?$/      app: "wingman-fips-poc-v1"/' \
  -e 's/^      app:[[:space:]]*[^#]+([[:space:]]*#.*)?$/      app: "wingman-fips-poc-v1"/' \
  -e 's/^    (#[[:space:]]*)?advertise:[[:space:]]*(true|false)$/      advertise: true/' \
  -e 's/^      advertise:[[:space:]]*(true|false)$/      advertise: true/' \
  -e '}' \
  -e '/^  udp:$/,/^  tcp:$/ {' \
  -e 's/^    (#[[:space:]]*)?advertise_on_nostr:[[:space:]]*(true|false)$/    advertise_on_nostr: true/' \
  -e '}' \
  "$TEMP"

require_line() {
  if ! grep -Eq "$1" "$TEMP"; then
    echo "FIPS config is not compatible with automatic Wingman PoC setup: missing $2" >&2
    echo "Original config preserved at $BACKUP" >&2
    exit 1
  fi
}

require_line '^    persistent: true$' 'node.identity.persistent'
require_line '^    nostr:$' 'node.rendezvous.nostr'
require_line '^      enabled: true$' 'node.rendezvous.nostr.enabled'
require_line '^      policy: open$' 'node.rendezvous.nostr.policy'
require_line '^      app: "wingman-fips-poc-v1"$' 'node.rendezvous.nostr.app'
require_line '^      advertise: true$' 'node.rendezvous.nostr.advertise'
require_line '^    advertise_on_nostr: true$' 'transports.udp.advertise_on_nostr'

chmod 600 "$TEMP"
mv "$TEMP" "$CONFIG"
trap - EXIT

if [ "${FIPS_SKIP_RESTART:-0}" != "1" ]; then
  launchctl kickstart -k system/com.fips.daemon
fi

echo "Configured FIPS for Wingman PoC rendezvous (existing identity preserved)."
