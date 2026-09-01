#!/bin/sh
set -eu

CONFIG="${FIPS_CONFIG_PATH:-/usr/local/etc/fips/fips.yaml}"
PLIST="${FIPS_LAUNCHD_PLIST:-/Library/LaunchDaemons/com.fips.daemon.plist}"
ATTESTATION="${FIPS_ATTESTATION_PATH:-/usr/local/etc/fips/wingman-poc-runtime.json}"

if [ "$(id -u)" -ne 0 ] && [ "${FIPS_CONFIG_TEST:-0}" != "1" ]; then
  echo "This helper must run as root through WMapp's explicit FIPS activation." >&2
  exit 1
fi
if [ ! -f "$CONFIG" ] || [ ! -f "$PLIST" ]; then
  echo "FIPS v0.5.0 did not install its expected config or launch daemon." >&2
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
  -e 's/^    (#[[:space:]]*)?share_local_candidates:[[:space:]]*(true|false)$/      share_local_candidates: true/' \
  -e 's/^      share_local_candidates:[[:space:]]*(true|false)$/      share_local_candidates: true/' \
  -e '}' \
  -e '/^    (#[[:space:]]*)?lan:$/,/^tun:$/ {' \
  -e 's/^    (#[[:space:]]*)?lan:$/    lan:/' \
  -e 's/^    (#[[:space:]]*)?enabled:[[:space:]]*(true|false)$/      enabled: true/' \
  -e 's/^      enabled:[[:space:]]*(true|false)$/      enabled: true/' \
  -e 's/^    (#[[:space:]]*)?(#[[:space:]]*)?scope:[[:space:]]*[^#]+([[:space:]]*#.*)?$/      scope: "wingman-fips-poc-v1"/' \
  -e 's/^      scope:[[:space:]]*[^#]+([[:space:]]*#.*)?$/      scope: "wingman-fips-poc-v1"/' \
  -e '}' \
  -e '/^tun:$/,/^dns:$/ {' \
  -e 's/^  (#[[:space:]]*)?enabled:[[:space:]]*(true|false)$/  enabled: true/' \
  -e '}' \
  -e '/^dns:$/,/^transports:$/ {' \
  -e 's/^  (#[[:space:]]*)?enabled:[[:space:]]*(true|false)$/  enabled: true/' \
  -e '}' \
  -e '/^  udp:$/,/^  tcp:$/ {' \
  -e 's/^    (#[[:space:]]*)?advertise_on_nostr:[[:space:]]*(true|false)$/    advertise_on_nostr: true/' \
  -e 's/^    (#[[:space:]]*)?accept_connections:[[:space:]]*(true|false).*$/    accept_connections: true/' \
  -e 's/^    (#[[:space:]]*)?outbound_only:[[:space:]]*(true|false).*$/    outbound_only: false/' \
  -e '}' \
  "$TEMP"

# v0.5.0 understands this option but its packaged example does not contain it,
# so insert it inside the Nostr rendezvous section when there was no existing
# active or commented value for the transform above.
if ! sed -n '/^    nostr:$/,/^    lan:$/p' "$TEMP" | \
  grep -Eq '^      share_local_candidates: true$'; then
  sed -i '' '/^    lan:$/i\
      share_local_candidates: true
' "$TEMP"
fi

require_line() {
  if ! grep -Eq "$1" "$TEMP"; then
    echo "FIPS config is not compatible with automatic Wingman PoC setup: missing $2" >&2
    echo "Original config preserved at $BACKUP" >&2
    exit 1
  fi
}

require_section_line() {
  if ! sed -n "/$1/,/$2/p" "$TEMP" | grep -Eq "$3"; then
    echo "FIPS config is not compatible with automatic Wingman PoC setup: missing $4" >&2
    echo "Original config preserved at $BACKUP" >&2
    exit 1
  fi
}

require_line '^    persistent: true$' 'node.identity.persistent'
require_line '^    nostr:$' 'node.rendezvous.nostr'
require_section_line '^    nostr:$' '^    lan:$' '^      enabled: true$' 'node.rendezvous.nostr.enabled'
require_section_line '^    nostr:$' '^    lan:$' '^      policy: open$' 'node.rendezvous.nostr.policy'
require_section_line '^    nostr:$' '^    lan:$' '^      app: "wingman-fips-poc-v1"$' 'node.rendezvous.nostr.app'
require_section_line '^    nostr:$' '^    lan:$' '^      advertise: true$' 'node.rendezvous.nostr.advertise'
require_section_line '^    nostr:$' '^    lan:$' '^      share_local_candidates: true$' 'node.rendezvous.nostr.share_local_candidates'
require_line '^    lan:$' 'node.rendezvous.lan'
require_section_line '^    lan:$' '^tun:$' '^      enabled: true$' 'node.rendezvous.lan.enabled'
require_section_line '^    lan:$' '^tun:$' '^      scope: "wingman-fips-poc-v1"$' 'node.rendezvous.lan.scope'
require_section_line '^tun:$' '^dns:$' '^  enabled: true$' 'tun.enabled'
require_section_line '^dns:$' '^transports:$' '^  enabled: true$' 'dns.enabled'
require_section_line '^  udp:$' '^  tcp:$' '^    advertise_on_nostr: true$' 'transports.udp.advertise_on_nostr'
require_section_line '^  udp:$' '^  tcp:$' '^    accept_connections: true$' 'transports.udp.accept_connections'
require_section_line '^  udp:$' '^  tcp:$' '^    outbound_only: false$' 'transports.udp.outbound_only'

chmod 600 "$TEMP"
if [ "${FIPS_CONFIG_TEST:-0}" != "1" ]; then
  chown root:wheel "$TEMP"
fi
mv "$TEMP" "$CONFIG"
trap - EXIT

ATTESTATION_TEMP="${ATTESTATION}.tmp.$$"
trap 'rm -f "$ATTESTATION_TEMP"' EXIT
cat > "$ATTESTATION_TEMP" <<'EOF'
{"schema":1,"fipsVersion":"0.5.0","rendezvousApp":"wingman-fips-poc-v1","nostrShareLocalCandidates":true,"lanEnabled":true,"lanScope":"wingman-fips-poc-v1","tunEnabled":true,"dnsEnabled":true,"udpAdvertiseOnNostr":true,"udpAcceptConnections":true,"udpOutboundOnly":false}
EOF
chmod 0644 "$ATTESTATION_TEMP"
if [ "${FIPS_CONFIG_TEST:-0}" != "1" ]; then
  chown root:wheel "$ATTESTATION_TEMP"
fi
mv "$ATTESTATION_TEMP" "$ATTESTATION"
trap - EXIT

if [ "${FIPS_SKIP_RESTART:-0}" != "1" ] && [ "${FIPS_CONFIG_TEST:-0}" != "1" ]; then
  launchctl kickstart -k system/com.fips.daemon
fi

echo "Configured bundled FIPS for Wingman mesh access (existing identity preserved)."
