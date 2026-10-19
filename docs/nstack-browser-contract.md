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
the exact `GET /api/v4/workspaces?member_npub=<active identity npub>` URL with
the same unlocked identity exposed through `window.nostr`. It allowlists the
returned safe fields and ignores wrapped secrets or other response fields.
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
  directHttpsUrl: string; // Tower value when supplied, otherwise NStack URL
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

NBrowser self-encrypts the canonical snapshot with NIP-44 v2, then uses Tower's
existing immutable private object flow: signed prepare, signed upload,
hash-checked complete, and signed metadata/content fetch. A signed parameterized
replaceable kind `30078` event uses the stable `d` tag
`org.wingman.nbrowser.settings.v1`. Its NIP-44 self-encrypted content contains
only the host URL, optional workspace identifier, exact object UUID and SHA-256,
snapshot schema/revision/time, and recovery relay URLs.

Recovery accepts only an exactly authored, correctly signed kind-30078 event
with that `d` tag. It decrypts and validates the pointer, retrieves that exact
private object, checks Tower metadata and the downloaded bytes against the
expected hash, decrypts and validates the identity/schema/revision, then shows a
preview. The local registry is a single-record atomic replacement only after
explicit confirmation. Any missing, malformed, stale/conflicting, undecryptable,
or tampered input leaves current settings untouched.

Automated tests use fake storage and relays; they never publish real events.
The manual fixture is [`app/web/nstack-test.html`](../app/web/nstack-test.html).
