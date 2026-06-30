# Wingman App

Wingman App is the planned native edge client for Wingman Be Free.

The initial product combines:

- Wingman Drive: a desktop/mobile file surface backed by Tower HTTP storage.
- Wingman Browser: an embedded browser for Flight Deck and WApps with native Nostr signing.
- Wingman Signer: local per-device Nostr key custody for NIP-98 and approved app signing.

Tower remains the source of truth for workspace identity, scopes, channels, groups, file metadata, and object storage.

## Native Core

The first Rust core crate lives at `crates/wmapp-core`.

Useful commands:

```bash
cargo test
cargo run --bin wmapp-core -- status
cargo run --bin wmapp-core -- device generate --show-secret
cargo run --bin wmapp-core -- sign-nip98 --secret <hex-or-nsec> --method POST --url https://tower.example/api --body '{"hello":"wingman"}'
```

See:

- [Architecture](docs/architecture.md)
- [Decision Backlog](docs/decisions.md)
- [Implementation Plan](docs/implementation_plan.md)
- [Tower Route Inventory](docs/tower_route_inventory.md)
- [Tower Drive Contract](docs/tower_drive_contract.md)
- [Device Key Contract](docs/device_key_contract.md)
- [API Gap Harness](docs/api_gap_harness.md)
