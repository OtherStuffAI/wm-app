# Wingman App

Wingman App is the planned native edge client for Wingman Be Free.

The initial product combines:

- Wingman Drive: a desktop/mobile file surface backed by Tower HTTP storage.
- Wingman Browser: an embedded browser for Flight Deck and WApps with native Nostr signing.
- Wingman Signer: local per-device Nostr key custody for NIP-98 and approved app signing.

Tower remains the source of truth for workspace identity, scopes, channels, groups, file metadata, and object storage.

See:

- [Architecture](docs/architecture.md)
- [Implementation Plan](docs/implementation_plan.md)
