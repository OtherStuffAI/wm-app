# NStack Browser Contract v1

Status: implemented foundation
Protocol version: `1`

## Boundary

`window.NStack` is origin-consented secure connection autofill.
It is not a network transport, authentication provider, or signer. Applications
use normal HTTPS themselves, use `window.fipsTransport` for approved private
FIPS connections, and request fresh exact NIP-98 signatures through
`window.nostr`. A connection descriptor never contains an `nsec`, administrator secret,
bearer token, reusable signature, or browser-wide inventory.

The native NStacks screen accepts only a canonical HTTPS address (or approved
loopback HTTP address). On first save and every refresh NBrowser freshly signs
both exact Tower list URLs with the same active, unlocked native identity
exposed through `window.nostr`:

- `GET /api/v4/workspaces?member_npub=<active identity npub>` for legacy
  creator-owned and group-member workspaces;
- `GET /api/v4/flightdeck-pg/workspaces?limit=200` for Flight Deck PG owner and
  member workspaces. When that response supplies an opaque `next_cursor`,
  NBrowser follows it as the exact `cursor` query value, freshly signs every
  page URL, rejects repeated/invalid cursors, and stops at bounded page and
  total-workspace limits.

Logging into a website inside a tab does not select or replace this native
identity. NBrowser validates and merges both response shapes, allowlists only
the safe connection fields, and ignores wrapped secrets or other response
fields. For Flight Deck summaries, `directHttpsUrl` is always the canonical
address that successfully carried the freshly signed discovery request,
including its configured base path. Tower's serialized `tower_base_url` is
checked as a routing hint, not trusted as replacement authority. A reverse
proxy's HTTP downgrade is tolerated only for the same host, a standard
proxy-side HTTP port, and a compatible path; a different authority, custom
port, or path fails closed, and the downgraded URL is
never persisted or disclosed. An explicit PG `v4_workspace_id` identifies the
same logical workspace across both lists; the PG descriptor is retained because
it carries the canonical PG workspace ID, while the legacy link is retained
only as private registry merge metadata so existing origin-scoped aliases
remain stable. That merge metadata is not part of `window.NStack` results. For
a legacy descriptor, `creator_npub` is the human workspace owner while
`workspace_service_npub` (or its `workspace_npub` alias) remains the distinct
workspace service identity.

A Tower that clearly does not implement the Flight Deck collection route (HTTP
404, 405, or 501 on the first PG request) remains a valid legacy-only NStack.
Authentication/authorization failures, server failures, malformed responses,
and failures after pagination has begun fail the combined refresh visibly and
retain the previous list as stale; they are never treated as a successful
partial discovery.
An individually unusable historical PG summary can be omitted when valid,
unambiguous siblings remain. Duplicate workspace or linked identities and
pages containing records but no usable identity still fail the refresh.
First-save failure stores nothing. A later transient failure retains the last
successful list, visibly marks it stale, and never invents a workspace.

The provider is installed only in a verified top-level HTTPS document or an
approved loopback/local document. Before discovery consent, a document can
observe only that the API exists, `version === 1`, and the result of
`isAvailable()` (`{available: true, version: 1}`). Listing calls fail with
`not_disclosed`.

## JavaScript API

```ts
type NStackErrorCode =
  | "unavailable"
  | "locked"
  | "consent_denied"
  | "not_disclosed"
  | "invalid_request"
  | "stale_handle"
  | "stack_unavailable";

interface NStackError extends Error { code: NStackErrorCode }

interface NStackSummary {
  id: string;       // random, opaque and scoped to origin + signer identity
  name: string;
  url: string;      // canonical saved HTTPS address
  host: boolean;
  available: true;
  stale: boolean;
  lastRefreshedAt: string | null;
}

interface WorkspaceSummary {
  id: string;       // independently opaque and origin/identity scoped
  name: string;
  workspaceId: string; // real remote workspace identity used by app setup
  workspaceOwnerNpub: string;
  workspaceServiceNpub: string;
  directHttpsUrl: string; // verified canonical NStack discovery address
  serviceNpub?: string; // Tower service identity when supplied by Tower
  nstack: {
    id: string;     // same origin-scoped NStack alias
    name: string;
    url: string;
  };
}

interface WindowNStackV1 {
  readonly version: 1;
  isAvailable(): Promise<{available: true; version: 1}>;
  requestDiscovery(options?: {workspaces?: boolean}): Promise<{
    disclosed: number;
    workspaces: boolean;
  }>;
  listNStacks(): Promise<NStackSummary[]>;
  listWorkspaces(input: {stackId: string}): Promise<WorkspaceSummary[]>;
  getConnection(input: {
    stackId: string;
    workspaceId: string; // origin-scoped workspace alias, not the remote ID
  }): Promise<WorkspaceSummary>;
  /** @deprecated Compatibility only; always rejects with invalid_request. */
  requestCapabilities(options?: unknown): Promise<never>;
  revoke(): Promise<true>; // revokes this origin's discovery consent
  on(name: "change", handler: (event: {reason: string}) => void): () => void;
}
```

`listWorkspaces` and `getConnection` return the same safe descriptor shape.
Flight Deck, Ambulando, and Canopy may copy `directHttpsUrl`, `workspaceId`,
`workspaceOwnerNpub`/`workspaceServiceNpub`, and `serviceNpub` into their normal
connection forms. They then authenticate normally with fresh `window.nostr`
NIP-98 signatures. No Tower capability, service permission, credential, or
transport authority is implied.

`requestCapabilities()` remains present only because it was part of the public
v1 API. It deterministically rejects locally with `invalid_request` and does
not dispatch to native code, show approval UI, create a handle, persist a rule,
or grant authority. New and existing consumers must use connection discovery;
the method is deprecated and is not a feature-detection signal for authority.

The provider also exposes `window.NStackReady`, a Promise resolving to the v1
provider, and dispatches a top-level `nstackready` event. On WebKit and supported
Android WebViews a frozen queuing provider is installed at document start, so
application startup can call it immediately. The ready Promise/event is the
deterministic fallback contract on hosts where only post-load installation is
available. Consumers should feature-detect immediately, then await
`window.NStackReady` or listen once for `nstackready` before declaring the
bridge unavailable.

## Consent and lifecycle

Discovery opens a native NBrowser selector and persists only the selected
origin rule for the active signer identity. Stack and workspace IDs are fresh
opaque aliases within that origin/identity scope. Discovery is not service
authority.

There is no second capability approval or handle. Navigation/document
replacement and tab close invalidate pending bridge calls; signer lock and
identity change fail closed; a different top-level origin cannot use another
origin's aliases; `revoke()` removes the calling origin's discovery rule and
all subsequent access. `requestCapabilities()` retains its v1 method name for
compatibility but cannot create a service capability handle. `revoke()`
continues to revoke only the calling origin's discovery consent.
Registry refresh/removal is checked on each listing or descriptor request. The
`change` listener reports visible changes; callers must re-list and must not
treat an event as authority. NBrowser's NStacks screen lists and revokes
persistent origin discovery rules.

## Error semantics

- `unavailable`: provider/runtime or configured NStack is absent.
- `locked`: the signer is locked or no active identity exists.
- `consent_denied`: the native discovery prompt was declined.
- `not_disclosed`: the origin has no matching disclosure or opaque ID.
- `invalid_request`: malformed fields or a request that cannot be bound to the
  verified top-level document.
- `stale_handle`: retained compatibility error name for a replaced/revoked
  document or expired pending request; no service capability handle is issued.
- `stack_unavailable`: a previously disclosed stack/workspace was removed.

Errors reject the Promise with an `Error` whose stable `code` has one of these
values. Messages are explanatory and are not protocol-stable.

## Settings backup and recovery

Existing v1 registry rows containing manually entered workspace names/IDs still
parse for rollback and backup compatibility. They are not disclosed as usable
connections until an authenticated refresh replaces/merges them by stable
remote workspace identity. Matching rows retain their origin-scoped internal
alias; rows no longer returned by Tower are removed. NStack browser links,
active/host selection, background, label colour, and startup choice are
preserved.

The versioned settings snapshot includes only the NStack registry and safe
per-stack browser settings (links, launcher background, label colour, and
startup selection). It excludes signer/vault secrets, secure-storage values,
origin grants, signatures, tokens, browsing sessions, cookies,
cache, and unrelated application settings. Existing identity-scoped v1 browser
links are copied into the first active NStack once and retained in their legacy
record for rollback.

The user explicitly chooses one discovered Flight Deck workspace across all
saved NStacks. NBrowser persists that destination per unlocked identity as the
stable local NStack alias plus the local and remote workspace identities and
the discovered workspace owner npub. Refresh, removal, stale discovery, or
membership loss never substitutes another workspace. A legacy `host_stack_id`
is migrated once only when that stack still has exactly one accessible Flight
Deck workspace; ambiguous or unavailable legacy state requires a user choice.

The public NBrowser namespace is
`npub104qc4t62zry5vrqnsevkazswgtdh87fy2vgc73sndellfnq7pa2sqrqjs0`.
It is derived without a secret by hashing UTF-8 candidates
`org.wingman.nbrowser.app-namespace.v1:<counter>` with SHA-256, starting at
decimal counter zero, and choosing the first digest whose 32-byte value lifts
to a secp256k1 x-coordinate using the compressed even-y prefix `02`. Counter
zero is valid, producing x-coordinate
`7d418aaf4a10c9460c1386596e8a0e42db73f92453118f46136e7ff4cc1e0f55`,
which is Bech32-encoded as the `npub` above. This is a deterministic release
namespace identifier, not a signer identity; no corresponding secret is
generated, embedded, stored, or used by NBrowser.

A workspace manager enables the namespace with capabilities
`storage.private` and `app_rows.private_only`. Missing or disabled registration
is shown explicitly. An ordinary member is told to ask a workspace manager;
NBrowser does not retry or degrade to host-level storage.

NBrowser self-encrypts the canonical snapshot with NIP-44 v2, then prepares it
through
`POST /api/v4/flightdeck-pg/workspaces/{workspaceId}/storage/prepare` without
legacy owner/group fields. It uses the existing freshly signed upload,
hash-checked complete, metadata, and content routes. The authoritative pointer
is the signing human's private `current-v1` row in collection
`settings-backups` under the public NBrowser namespace. Every app-row response
must bind to the selected workspace UUID and discovered workspace-owner npub.

A signed parameterized replaceable kind `30078` event still uses the stable `d`
tag `org.wingman.nbrowser.settings.v1`. Its NIP-44 self-encrypted content
contains only the selected host/workspace binding, exact object UUID and
SHA-256, snapshot schema/revision/time, and recovery relay URLs. The hint is
supplementary: recovery reads the selected workspace's private row first, and
an absent, legacy, malformed, or inconsistent hint can never override that
selection.

Recovery validates the private row's workspace, object, hash, status, revision,
and timestamp, retrieves that exact private object, checks Tower metadata and
downloaded bytes, decrypts and validates identity/schema/revision locally, then
shows a preview. Old version-1 snapshots and optional old hint fields remain
parseable. The local registry is a single-record atomic replacement only after
explicit confirmation. Any missing namespace, lost membership, unavailable
destination, mismatched response, malformed row, undecryptable snapshot, or
tampered input leaves current settings untouched.

Automated tests use fake storage and relays; they never publish real events.
The manual fixture is [`app/web/nstack-test.html`](../app/web/nstack-test.html).
