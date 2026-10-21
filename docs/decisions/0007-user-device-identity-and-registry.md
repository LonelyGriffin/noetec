# 0007: Multi-User Identity and Sync Registry Model

## Context

File-based sync exchanges state only through the `.sync/` directory; `.noetec/`
holds local, non-synced metadata (vault.json, device.json, trusted_keys.json,
WAL, conflicts). The product needs real multi-user support: several users per
vault, each with several devices, with attribution ("which user made this
entry") and authorization ("only authorized users/devices contribute").

"user = owner device" was rejected: a user must exist independently of any
single device and be recoverable. Server-based identity (passkey/OIDC) and
data-first registries were rejected for the file-based phase (see Alternatives).
The chosen model is hierarchical cryptographic identity with seed recovery.

## Decision

### 1. Identity (two levels)

- A **user** is an Ed25519 identity key pair derived deterministically from a
  32-byte seed (backed up as a BIP39 mnemonic).
- A **device** is an independent Ed25519 key pair, one per machine, NOT derived
  from the seed — so a device can be revoked without touching the identity.
- A device is bound to its user by a **certificate**:
  `{deviceUuid, devicePublicKey, userId, deviceName, issuedAt}`, signed by the
  user's identity key.
- The identity key is derived from the seed with **HKDF-SHA256** (RFC 5869):
  `salt = "noetec.identity.v1"`, `info = "noetec-identity-key"`, 32-byte output
  used as the Ed25519 secret seed. The mnemonic is only a human-readable backup
  of the seed (restored via `mnemonicToEntropy`); PBKDF2 is not used.

Attribution chain: `entry → device (device key) → user (certificate) →
authorized (registry)`.

### 2. Secrets

Seed, identity private key, and device private key live in
`flutter_secure_storage`; they MUST NOT be written to the vault or the sync
zone. The seed is shown once at identity creation for backup.

### 3. Registries

- `.sync/users.json` — one owner-signed registry of users. Each record:
  `{userId, name, publicKey, role, addedBy, updatedAt, removedAt, signature}`.
  The file carries `{version, revision, parent, owner_user_id, users,
  signature}` (whole-file signature by the owner identity key; each record
  signed by `addedBy`).
- `.sync/devices/<userId>.json` — one file per user, signed by that user's
  identity key (whole-file + per-record). The unique file name makes it
  conflict-free by construction (same principle as OpLog): each user manages
  only their own file, so two users adding devices never conflict.

### 4. Roles

`role: owner | member` on user records. Only `owner` is enforced for v1 (owner
administers `users.json`). Fine-grained roles are deferred to server sync —
they are not enforceable under file-based sync.

### 5. Registry merge (users.json)

Version stamps are HLC keys (`<physicalMs>-<counter>-<deviceId>`, component-wise
ordering — see `lib/entity/hlc.dart`). Conflict resolution is **LWW per-record**,
not per-file: for each record compare `updatedAt` / `removedAt` (tombstone) by
HLC; identical HLC ties are broken deterministically by canonical JSON. A 3-way
merge uses `parent` as the common ancestor. File-level LWW (larger `revision`)
is only a fallback when no common ancestor exists, and it always reports rather
than silently dropping.

## Status

Accepted.

Revised 2026-09-08: withdrew the PBKDF2 clause in §1 (it contradicted the first
bullet and the HKDF clause). The identity key derives from the 32-byte entropy
seed via HKDF-SHA256; the mnemonic is only a backup. PBKDF2 is not part of
derivation.

Supersedes ADR-0003 (device identity deferred): device identity is now
implemented (`lib/entity/device/device_identity.dart`,
`lib/service/device_service.dart`). The `modified_by` frontmatter field remains
deferred/optional — attribution lives in the OpLog (deviceId + signature).

## Consequences

- Positive: real multi-user with per-user device management; full attribution
  `entry → device → user`; identity recoverable from seed; device revocation
  independent of identity; registries converge deterministically under
  concurrent edits.
- Positive: `devices/<userId>.json` removes the "concurrent devices.json"
  conflict class and lets every registry file carry a whole-file signature.
- Negative: two key pairs and two registry kinds (more concepts/code).
- Negative: the identity key (or seed) is present on every device of a user,
  so compromising one device compromises the identity.
- Negative (inherited file-based limit, unchanged from sync-security.md): no
  physical write prevention (rejection happens at read time).

## Alternatives considered

- **user = owner device** — rejected: no independent user, no recovery.
- **Flat model (user = named group of devices)** — rejected: user has no
  cryptographic identity; losing all devices loses the user.
- **Data-first registry (users as OpLog-synced documents)** — rejected:
  bootstrap cycle and harder security analysis.
- **External identity (passkey/OIDC)** — deferred to the server version: adds a
  trusted third party and an online dependency, conflicting with local-first.
- **Single `devices.json`** — rejected: concurrent edits by different users
  require merge without a whole-file signer; per-user files avoid the conflict
  class and stay fully signed.
- **Per-file LWW (no merge)** — rejected: silently drops concurrent additions to
  different records.
- **SLIP-0010 (BIP32 for Ed25519) for the identity key** — rejected: adds a
  chain code and hierarchical derivation, which this model does not need (the
  identity key is a single key; device keys are independent), and requires more
  code for no benefit.
- **SHA-256(seed) as the KDF** — rejected: no domain separation and not a
  key-derivation standard.
