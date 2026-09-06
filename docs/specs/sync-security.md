# Noetec Sync Security Extensions

**Format version: 1 (draft)**

This document is the normative specification of the security extensions to the
Noetec sync operation log (OpLog) entry format: signatures, user & device
authorization, witness references, and key-trust validation. Implementations
**MUST** conform to it; divergence is a bug in the implementation, not in this
document.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
are interpreted as described in RFC 2119.

The base entry format (wire keys `v`, `hlc`, `parent`, `parent_b`, `type`,
`device`, `block_ops`, `file_op`, `file_hash`), the HLC key format, and the
on-disk layout of device files are defined by the existing codebase
(`lib/systems/oplog_system/oplog_serializer.dart`); this document extends that
format. Where the signing input references an entry (§2.2), it is the **wire
representation** (snake_case keys) that is serialized and signed. `docs/specs/file-format.md` is the style and
format reference; where the two documents overlap, this document is
authoritative for the sync security extensions.

The extensions are defined in four phases, all backward compatible with
unsigned legacy data (§8):

- **Phase 1 — Signatures** (mandatory): every entry is signed with the
  authoring device's Ed25519 key.
- **Phase 2 — User & device registries**: per-user device registries and an
  owner-signed user registry.
- **Phase 3 — Witness fields** (`seen`): each entry records the latest entries
  it observed from other devices, making truncation detectable.
- **Phase 4 — TOFU and HLC drift validation**: trust-on-first-use key pinning
  and rejection of implausible timestamps.

---

## 1. Overview

### 1.1 Storage layout

One append-only JSONL file per device per page:

```text
.sync/pages/<encoded-path>/<deviceId>.oplog.jsonl
```

- Each device appends **only** to its own file, keeping filesystem sync
  (WebDAV/Dropbox) conflict-free; conflict resolution moves to the DAG level.
- The file name uses the device's `deviceUuid` (as do `deviceId` and HLC
  keys). Extensions **MUST NOT** change this.
- The local device identity, including its public key, lives in
  `.noetec/device.json`.
- This document defines more files: `.sync/users.json` and
  `.sync/devices/<userId>.json` (Phase 2) and `.noetec/trusted_keys.json`
  (Phase 4).

### 1.2 Entry format, extended

New fields on an entry; existing keys are unchanged:

| Field       | Type           | Phase | Present          | Description                                      |
| ----------- | -------------- | ----- | ---------------- | ------------------------------------------------ |
| `signature` | string         | 1     | MUST*            | Ed25519 signature over the entry, base64url.     |
| `pubKey`    | string or null | 1     | first entry only | Base64url Ed25519 public key of the authoring device. |
| `seen`      | map or null    | 3     | SHOULD           | Witness references `{deviceId: lastSeenHlcKey}`. |

\* Mandatory for Phase-1 implementations; entries without `signature` are
legacy and accepted during migration (§8.1).

### 1.3 Threat model

The adversary has **read/write access to the shared sync folder** — able to
read, append, truncate, or replace oplog files and the registry files — but
does **not** possess any device's private key. Out of scope: an adversary with
access to a device's secure key storage, and one able to tamper with *all*
devices at once (the first legitimate observation of a key is always trusted,
§5.2).

---

## 2. Phase 1 — Cryptographic signatures

### 2.1 Keys

- The signature algorithm **MUST** be Ed25519.
- There are **two** key kinds (see ADR-0007 for the derivation rationale):
  - a **user identity key** — an Ed25519 key pair shared by every device of
    one user, derived deterministically from a seed; and
  - a **device key** — an independent Ed25519 key pair, one per machine,
    generated at first device registration (**SHOULD**), **not** derived from
    the seed.
  A device is bound to its user by a **certificate** signed by the user's
  identity key (§3).
- Every **public key** is the 32-byte Ed25519 key, **MUST** be base64url-
  encoded (RFC 4648 §5, no padding), and **MUST** be stored:
  - the **device** public key — in `device.json` (`public_key` JSON key) for
    the local device, and in the **first entry** of the device's oplog file
    (`pubKey` field), so other devices can obtain it during sync;
  - the **identity** public key — in the user registry `users.json`
    (`publicKey` field, §3).
- **Encoding migration.** Legacy `device.json` files encode `public_key` as
  standard base64 **with** padding (RFC 4648 §4); the current device-key
  generator (`lib/service/crypto_service.dart`) still emits this padded form
  via `base64Encode`. On first Phase-1 read, an implementation **MUST** detect
  the legacy form (the value contains `+`, `/`, or `=`), decode it, and
  re-encode as base64url; it **MAY** rewrite the file on first write. All wire
  formats defined here (entries, registry files, `trusted_keys.json`) **MUST**
  use base64url exclusively.
- **Private keys and the seed** **MUST NOT** be stored in the sync folder or
  any plain file; the seed, the identity private key, and the device private
  key **MUST** live in platform secure storage (`flutter_secure_storage`).
  Only the authoring device may produce signatures for its `deviceUuid`; only
  a user's devices may produce signatures for that user's `userId`.
- `deviceUuid` **MUST** remain the identity in HLC keys, `deviceId`, and file
  names.

### 2.2 Signing input

The signature is computed over:

```text
signingInput = canonicalJson(entryWithoutSignature) + documentPath
```

- `entryWithoutSignature` is the entry object **without** `signature`; all
  other keys (including `pubKey`) **MUST** be present exactly as serialized —
  i.e. the wire representation with snake_case keys (`v`, `hlc`, `parent`,
  `parent_b`, `type`, `device`, `block_ops`, `file_op`, `file_hash`).
- `documentPath` is the page path relative to the vault root, no extension,
  `/` separators (e.g. `notes/ideas`), appended with no separator.

`canonicalJson(obj)` **MUST** serialize: keys sorted lexicographically (UTF-8
code point order), no whitespace beyond `,`/`:`, UTF-8 strings, arrays in
stored order (order is significant). `null`-valued keys **MAY** be omitted; an
implementation that omits them on write **MUST** omit them on verify.

### 2.3 Signature rules

- On **write**, a device **MUST** sign `signingInput` with its Ed25519 private
  key and store the 64-byte signature, base64url (no padding), in `signature`.
- `pubKey` **MUST** be present on the **first entry** (the entry with no
  `parent`), **MUST** equal the key in `device.json`, and **MUST NOT** appear
  on later entries.

### 2.4 Verification rules

Processing each device file from first to last entry:

1. **First entry** **MUST** contain a non-null `pubKey`; one without it is a
   legacy entry (§8.1) and does not by itself invalidate the file.
2. **Every signed entry** **MUST** verify: a valid Ed25519 signature of
   `signingInput` (§2.2) under the device key (`pubKey` from the first entry,
   or `device.json` for the local device).
3. **Chain rejection.** If a signature fails (or the entry is structurally
   unverifiable), reject that entry **and all subsequent entries in the file**.
   Earlier valid entries remain in the DAG.
4. **Re-keying** **MUST NOT** be accepted silently: a changed public key
   **MUST** trigger the TOFU rules (§5.2).
5. Legacy (unsigned) entries do not start a chain rejection; signed entries
   after them are verified as usual (§8.1).
6. Rejected entries **MUST NOT** contribute to the DAG, merge decisions, or
   witness state, and **MUST** be reported (§9).

---

## 3. Phase 2 — User & device registries

### 3.1 Purpose

Phase 1 binds each entry to a **device key** (§2.4). Phase 2 binds that device
to a **user** and restricts which users may contribute. Two registry files in
the synced `.sync/` area define the authorization model:

- `.sync/users.json` — the **user registry**, one per vault, signed by the
  owner's identity key.
- `.sync/devices/<userId>.json` — a **device registry** per user, signed by
  that user's identity key.

The attribution chain is:

```text
entry → device (device key, §2) → user (certificate) → authorized (registry)
```

### 3.2 User registry (`users.json`)

`.sync/users.json` (one per vault) **MUST** be a single JSON object:

```json
{
  "version": 1,
  "revision": "<HLC key>",
  "parent": "<HLC key of the previous revision, or null>",
  "owner_user_id": "<userId of the owner>",
  "users": [
    {
      "userId": "<user id>",
      "name": "<display name>",
      "publicKey": "<base64url Ed25519 identity public key>",
      "role": "owner | member",
      "addedBy": "<userId whose identity key signs this record>",
      "updatedAt": "<HLC key>",
      "removedAt": "<HLC key or null>",
      "signature": "<base64url Ed25519 signature>"
    }
  ],
  "signature": "<base64url Ed25519 signature over the whole file>"
}
```

Field semantics:

- `version` — **MUST** be the integer `1`.
- `revision` / `parent` — HLC keys. `revision` stamps this file version;
  `parent` is the previous `revision` (or `null` on the first). Together they
  form the merge history (§3.7).
- `owner_user_id` — **MUST** be present; the `userId` that administers this
  registry.
- `users` — **MUST** be present (empty is valid). Each record:
  - `userId` — **MUST** be unique (a UUID).
  - `name` — display name.
  - `publicKey` — the user's base64url identity key (§2.1).
  - `role` — `owner` or `member`. The owner's record **MUST** carry `owner`.
    Only `owner` is enforced in v1: the owner administers `users.json`.
  - `addedBy` — the `userId` whose identity key signs this record.
  - `updatedAt` — the HLC key of the last change to this record.
  - `removedAt` — the HLC key at which the user was removed, or `null`
    (tombstone; §3.6).
  - `signature` — Ed25519 over `canonicalJson(recordWithoutSignature)` (§2.2),
    by `addedBy`'s identity key.
- `signature` — whole-file Ed25519 over
  `canonicalJson(fileWithoutSignature)` (§2.2), by the **owner's** identity
  key.

### 3.3 Device registry (`devices/<userId>.json`)

`.sync/devices/<userId>.json` (one per user) **MUST** be a single JSON object:

```json
{
  "version": 1,
  "revision": "<HLC key>",
  "parent": "<HLC key of the previous revision, or null>",
  "userId": "<user id this file belongs to>",
  "devices": [
    {
      "deviceUuid": "<device uuid>",
      "devicePublicKey": "<base64url Ed25519 device public key>",
      "userId": "<user id>",
      "deviceName": "<display name>",
      "issuedAt": "<HLC key>",
      "updatedAt": "<HLC key>",
      "removedAt": "<HLC key or null>",
      "signature": "<base64url Ed25519 signature>"
    }
  ],
  "signature": "<base64url Ed25519 signature over the whole file>"
}
```

Field semantics:

- `version`, `revision`, `parent` — as in §3.2.
- `userId` — **MUST** equal the `userId` in the file name.
- `devices` — **MUST** be present (empty is valid). Each record is a device
  **certificate** (§2.1) plus merge fields:
  - `deviceUuid` — the device's `deviceUuid` (**MUST** be unique).
  - `devicePublicKey` — its base64url device key (§2.1).
  - `userId` — the owning user (**MUST** equal the file's `userId`).
  - `deviceName` — display name.
  - `issuedAt` — the HLC key at which the device was bound to the user.
  - `updatedAt` — the HLC key of the last change to this record.
  - `removedAt` — the HLC key at which the device was revoked, or `null`
    (tombstone; §3.6).
  - `signature` — Ed25519 over `canonicalJson(recordWithoutSignature)`, by the
    user's identity key.
- `signature` — whole-file Ed25519 over
  `canonicalJson(fileWithoutSignature)`, by the **user's** identity key.

The unique file name makes the device registry conflict-free by construction:
each user manages only their own file, so two users adding devices never
conflict. Two devices of the *same* user can still race; the same merge rules
apply (§3.7).

### 3.4 Signing and key resolution

- A writer **MUST** produce every whole-file and per-record signature above.
- A reader **MUST NOT** accept a registry file whose whole-file `signature`
  fails under the file's signing key (owner for `users.json`, the user for
  their `devices/<userId>.json`), or a record whose `signature` fails under
  its `addedBy`/user key.
- **Key resolution.** The owner's identity key is the root of trust: it is
  TOFU-pinned on first observation of `users.json` (§5). Other users' identity
  keys resolve from their `users.json` record. A device key resolves from the
  first entry's `pubKey` (§2.1) and is cross-checked against the certificate's
  `devicePublicKey`. An invalid registry **MUST** be treated as absent (§8.2)
  and reported.

### 3.5 Authorization check

With valid registries, an entry is **authorized** only if:

1. its `deviceId` is listed (and not `removedAt`) in some user's
   `devices/<userId>.json`, whose certificate verifies under that user's
   identity key and whose `devicePublicKey` equals the key that signed the
   entry; **and**
2. that user's `userId` is listed (and not `removedAt`) in `users.json`.

Any other entry is rejected; a rejected device's key **MUST NOT** be added to
the trust store (§5.1).

### 3.6 Adding and revoking

- **Add a user**: the owner signs a new `users` record (`addedBy` =
  `owner_user_id`), appends it, and re-signs `users.json`.
- **Remove a user**: the owner sets the record's `removedAt` (tombstone) and
  re-signs.
- **Add a device**: the user signs a new `devices` record in their own
  `devices/<userId>.json` and re-signs the file.
- **Revoke a device**: the user sets the record's `removedAt` and re-signs.
- Revocation is not retroactive — already-signed entries remain in the DAG;
  the revoked user/device just stops contributing new ones.
- Each update is an atomic file replacement; `revision`/`parent` advance
  (§3.7).

### 3.7 Registry merge (LWW, HLC)

Both registries are versioned documents merged with **last-write-wins per
record**, **not** per file:

- `revision` / `parent` are HLC keys forming a version chain (like OpLog
  entries). A 3-way merge uses `parent` as the common ancestor.
- For each record (keyed by `userId` in `users.json`, `deviceUuid` in
  `devices/<userId>.json`), compare `updatedAt` / `removedAt` by
  **component-wise HLC order** (§4.1) — `physicalMs`, then `counter`, then
  `deviceId`, never lexicographic.
- The record with the latest HLC wins. Identical HLC ties **MUST** be broken
  deterministically by `canonicalJson` (§2.2).
- A record with `removedAt` set is a **tombstone**: it removes the user/device
  regardless of `updatedAt` ordering, unless a newer record (later HLC)
  re-adds it.
- **File-level LWW** (larger `revision` wins) is only a fallback when no common
  ancestor exists; it **MUST** report the dropped side rather than silently
  discarding it.

---

## 4. Phase 3 — Witness fields

### 4.1 Field

An entry **MAY** carry `seen: Map<String, String>?` — `{deviceId:
lastSeenHlcKey}`.

- The key is another device's `deviceUuid` (never the entry's own).
- The value is the HLC key of the latest entry the author saw from that
  device: `<physicalMs>-<counter>-<deviceId>` — decimal `physicalMs`,
  lowercase-hex `counter` zero-padded to ≥4 chars, `deviceId` as UUID (e.g.
  `1756293123456-0001-7c1e2d3a-4b5f-4a6b-8c9d-0e1f2a3b4c5d`). This is the same
  string form as `hlc`/
  `parent`.
- **HLC ordering** is component-wise numeric — `physicalMs`, then `counter`,
  then `deviceId` — **not** lexicographic (variable-width `physicalMs` breaks
  string monotonicity). Implementations **MUST** parse components before
  comparing. Every "HLC-ordered" reference in this document means this.

### 4.2 Population

- On creating an entry, a device **SHOULD** map every *other* device to the
  latest HLC key it observed from it.
- A device **MUST NOT** list itself.
- `seen[d]` **MUST** be non-decreasing (HLC order) across the device's file,
  or absent.

### 4.3 Verification (truncation detection)

Witness references live in files the attacker does not control, so truncation
of *another* device's file becomes detectable:

- After building the DAG, for each `(d, hlcKey)` in an entry's `seen`: if
  device `d`'s file exists but has no entry HLC-ordered at or after `hlcKey`,
  the reference is **dangling**.
- Dangling references indicate the referenced file was truncated (attack or
  unrecoverable corruption). **MUST NOT** ignore silently: report the file and
  reference(s), and **SHOULD** treat that file's entries as untrusted (§9).
- A `seen` reference to a device whose file does not exist is **not** dangling
  (the device may be gone); **MAY** be ignored.

---

## 5. Phase 4a — Trust-on-first-use (TOFU)

### 5.1 Trusted keys file

`.noetec/trusted_keys.json` (outside the syncable `.sync` area) maps an
identifier to the base64url key first observed — a `deviceUuid` to its device
key, and a `userId` to its identity key:

```json
{
  "7c1e2d3a-4b5f-4a6b-8c9d-0e1f2a3b4c5d": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
```

(the value is a base64url 32-byte key — 43 chars, no padding)

The owner's identity key is pinned on first observation of `users.json` and is
the root of trust for the registries (§3.4).

### 5.2 TOFU rules

On first observing a key — a device's `pubKey`, or a user's identity key from
`users.json`:

1. Not in `trusted_keys.json` → **MUST** record it (first observation is
   trusted).
2. Present and **equal** → verify normally (§2.4).
3. Present and **different** → key substitution (file-replacement attack, or
   a device/user that lost its key): **MUST NOT** merge the file's entries,
   **MUST** warn the user and show both keys; the user **MAY** confirm the new
   key (then update `trusted_keys.json` and re-verify), otherwise the stored
   key stays authoritative.

### 5.3 Scope

Per-device/per-user local state: **MUST NOT** be synced or shared between
vaults; **MAY** be reset by the user (re-arming first-observation trust).

---

## 6. Phase 4b — HLC drift validation

HLC timestamps can be spoofed: an attacker may future-date `physicalMs` to
win merges (HLC orders by `physicalMs` first). When reading **other**
devices' entries, an implementation **MUST** check:

```text
entry.hlc.physicalMs <= localTime + maxDrift
```

`maxDrift` **SHOULD** default to 60 000 ms and **MAY** be configured larger.

- `physicalMs` within the bound is accepted.
- `physicalMs > localTime + maxDrift` **MUST** be treated as suspicious: not
  applied as a merge result without user awareness, **MUST** be reported, and
  **MAY** be rejected. The common policy **SHOULD** be to reject and surface
  in sync status.
- Past timestamps are valid (a slow device is not an attack).
- The check applies to *other* devices only.
- Suspicious entries **MUST** be logged (`package:logging`, never `print`).

---

## 7. Verification pipeline (normative order)

Checks **MUST** run in this order; a failure stops processing of the affected
entries:

1. **Parse** lines; invalid JSON lines are rejected in place.
2. **Signature** (§2.4) — verify the entry under its device key; on failure,
   reject entry + rest of chain.
3. **TOFU** (§5.2) — pin or reject the device key. TOFU runs **before** the
   registry filter so a new device's key is pinned before its authorization is
   judged.
4. **Certificate** (§3.3) — resolve the device to its user via
   `devices/<userId>.json` and verify the certificate.
5. **Registry filter** (§3.5) — reject devices whose user is not authorized in
   `users.json`.
6. **HLC drift** (§6) — reject/flag future timestamps.
7. **Witness consistency** (§4.3) — report dangling references.

Phases an implementation has not adopted are simply absent from the pipeline.

---

## 8. Backward compatibility

All extensions are additive; existing unsigned data **MUST** keep working.

### 8.1 Phase 1 — unsigned entries

- An entry without `signature` is **legacy** and **MUST** be accepted during
  migration.
- A file may mix legacy and signed entries; the first signed entry verifies
  against the file's first-entry `pubKey` (or `device.json`/trust store for
  the local device).
- **SHOULD** warn on legacy entries; **MAY** be configured (per vault) to
  reject unsigned entries once all devices migrate — opt-in hardening, the
  default **MUST** remain acceptance.
- A Phase-1 device **MUST** sign every entry it writes from then on.

### 8.2 Phase 2 — absent registry

- No `.sync/users.json` → document is **public**: any device with a valid key
  may contribute.
- Present but invalid (malformed or unverifiable) → treated as absent
  (public) and **MUST** be reported. A broken registry **MUST NOT** lock out
  devices.
- With a valid `users.json`, a device whose user is absent or `removedAt`, or
  whose certificate is missing or `removedAt`, is rejected per §3.5.

### 8.3 Phase 3 — absent `seen`

An entry without `seen` is valid; witness checks apply only to entries that
carry it. Phase-3 devices **SHOULD** include `seen` in every new entry.

### 8.4 Phase 4 — empty TOFU cache and drift

- Empty `trusted_keys.json` → every first observation is trusted and recorded.
- Not adopting drift validation: entries are accepted without the §6 check;
  adopting it later **MUST NOT** invalidate already-merged entries (it applies
  only to newly observed entries).

### 8.5 Serialization compatibility

- New fields are additional JSON keys: an implementation that does not know a
  key **MUST** ignore it on read and **MUST** preserve it on round-trip
  whenever feasible.
- These extensions do not change the entry `version`; a future incompatible
  change **MUST** bump the version and ship as a new spec version (as in
  `file-format.md`).

---

## 9. Reporting to the user

Implementations **MUST** surface (and log via `package:logging`) rather than
silently drop:

1. Failed signature (§2.4).
2. Non-registry device or user (§3.5).
3. TOFU key mismatch (§5.2) — show both keys, offer confirmation.
4. HLC drift violation (§6).
5. Dangling witness reference (§4.3) — name the file and key.
6. Legacy entries in a migrated document (§8.1).

---

## 10. Threat coverage matrix

Coverage of §1.3. Legend: ✅ fully, ⚠️ partially, ❌ not covered.

| # | Threat | P1 | P2 | P3 | P4 |
|---|---|---|---|---|---|
| 1 | Entry forgery (append under a victim's `deviceId`) | ✅ | ✅ | ✅ | ✅ |
| 2 | Unauthorized device participation | ❌ | ✅ | ✅ | ✅ |
| 3 | History truncation (roll back another device's file) | ⚠️ | ⚠️ | ✅ | ✅ |
| 4 | Replay (reuse a signature in another document) | ✅ | ✅ | ✅ | ✅ |
| 5 | HLC spoofing (future-date `physicalMs` to win merges) | ❌ | ❌ | ❌ | ✅ |
| 6 | Whole-file replacement (attacker's file under victim's name) | ❌ | ❌ | ❌ | ✅ |

- Threat 3 is only partially detected by Phase 1 (truncating the last entries
  can be invisible while the chain verifies); Phase 3's cross-references make
  it detectable.
- Threat 4 is closed by Phase 1 itself: `documentPath` is in the signing
  input (§2.2), so a copied signature does not verify in another document.
  Phase 4 adds nothing here (TOFU pins a key per *device*, not per document).

---

## 11. Performance overhead (estimates)

Order-of-magnitude guidance on a mid-range mobile device:

| Operation | Without signatures | With signatures (Phase 1) | Overhead |
|---|---|---|---|
| Write one entry | ~1 ms | ~5 ms | +4 ms |
| Read/verify 100 entries | ~10 ms | ~50 ms | +40 ms |
| Entry size | ~500 B | ~700 B | ≈ +40% |

- **Incremental verification (SHOULD):** cache per-entry results (keyed by
  HLC key) and verify only new lines.
- **Lazy verification (MAY):** verify only when building the DAG.
- **Batch signing (MAY, not in v1):** Merkle-root signing is out of scope for
  v1 and **MUST NOT** be mixed with per-entry signatures.

The registries add a small, constant number of signature verifications per
sync cycle (negligible); `seen` adds at most `O(other devices)` pairs per
entry.

---

## 12. Out of scope

- ADR rationale and rejected alternatives (centralized auth, consensus
  signing, shared-secret signing) — see the decision record.
- Migration, rollout, and test plans — implementation tasks.
- Platform file-access mechanics (macOS bookmarks, Android SAF) — they
  constrain key storage, not the format.
- Encryption of entry content — these extensions provide integrity,
  attribution, and authorization only; entries stay readable. Confidentiality
  is separate.

---

## 13. References

- RFC 2119 — Key words for use in RFCs.
- RFC 4648 — The Base16, Base32, and Base64 Data Encodings.
- Ed25519 — https://ed25519.cr.yp.to/
- Hybrid Logical Clocks (Kulkarni et al.) — https://www.cse.buffalo.edu/tech-reports/2014-04.pdf
- `docs/specs/file-format.md` — page file format (style reference).
- `docs/decisions/0007-user-device-identity-and-registry.md` — multi-user
  identity and registry model.
