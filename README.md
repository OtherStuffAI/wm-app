# Wingman App

Wingman App is the planned native edge client for Wingman Be Free.

The initial product combines:

- Wingman Drive: a desktop/mobile file surface backed by Tower HTTP storage.
- Wingman Browser: an embedded browser for Flight Deck and WApps with native Nostr signing.
- Wingman Signer: local per-device Nostr key custody for NIP-98 and approved app signing.

Tower remains the source of truth for workspace identity, scopes, channels, groups, file metadata, and object storage.

## Current Status

Phase 1 contracts and the Phase 2 headless native core are complete.

Latest package: `WP-02-05: Sync CLI And Local Control API`.

## Native Core

The first Rust core crate lives at `crates/wmapp-core`.

Useful commands:

```bash
cargo test
cargo run --bin wmapp-core -- status
cargo run --bin wmapp-core -- device generate --show-secret
cargo run --bin wmapp-core -- sign-nip98 --secret <hex-or-nsec> --method POST --url https://tower.example/api --body '{"hello":"wingman"}'
```

Tower read commands use NIP-98 signing. They accept flags or environment:

```bash
export TOWER_URL="http://127.0.0.1:3100"
export FLIGHTDECK_APP_NPUB="npub1hd37reqgfcnz3pvzj4grknd2nkzc94p9ercmunrxx22razr2rfxsw6dns5"
export WINGMAN_NSEC="<hex-or-nsec-device-or-agent-key>"

cargo run --bin wmapp-core -- status --workspace-id <workspace-id>
cargo run --bin wmapp-core -- list-files --workspace-id <workspace-id> --channel-id <channel-id>
cargo run --bin wmapp-core -- sync --once --workspace-id <workspace-id> --channel-id <channel-id>
cargo run --bin wmapp-core -- list-items --workspace-id <workspace-id>
cargo run --bin wmapp-core -- cat --workspace-id <workspace-id> <file-id> --output /tmp/file.out
cargo run --bin wmapp-core -- pin <file-id>
cargo run --bin wmapp-core -- evict <file-id> --force
```

See:

- [Architecture](docs/architecture.md)
- [Decision Backlog](docs/decisions.md)
- [Implementation Plan](docs/implementation_plan.md)
- [Tower Route Inventory](docs/tower_route_inventory.md)
- [Tower Drive Contract](docs/tower_drive_contract.md)
- [Device Key Contract](docs/device_key_contract.md)
- [API Gap Harness](docs/api_gap_harness.md)
