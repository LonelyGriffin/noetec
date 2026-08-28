# Noetec Sync Security Extensions

**Format version: 1 (draft)**

This document is the normative specification of the security extensions to the
Noetec sync operation log (OpLog) entry format: signatures, device
authorization, witness references, and key-trust validation. Implementations
**MUST** conform to it; divergence is a bug in the implementation, not in this
document.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
are interpreted as described in RFC 2119.

The base entry format (`version`, `hlc`, `parent`, `parentB`, `type`,
`blockOps`, `fileOp`, `fileHash`, `deviceId`), the HLC key format, and the
on-disk layout of device files are defined by the existing codebase; this
document extends that format. `docs/specs/file-format.md` is the style and
format reference.

The extensions are defined in four phases, all backward compatible with
unsigned legacy data (§8):

- **Phase 1 — Signatures** (mandatory): every entry is signed with the
  authoring device's Ed25519 key.
- **Phase 2 — Device authorization manifest**: an allow-list of devices.
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
- This document defines two more files: `.sync/.manifest.json` (Phase 2) and
  `.noetec/trusted_keys.json` (Phase 4).

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
read, append, truncate, or replace oplog files and the manifest — but does
**not** possess any device's private key. Out of scope: an adversary with
access to a device's secure key storage, and one able to tamper with *all*
devices at once (the first legitimate observation of a key is always trusted,
§5.2).

---

## 2. Phase 1 — Cryptographic signatures

### 2.1 Keys

- The signature algorithm **MUST** be Ed25519.
- Each device holds exactly one key pair per vault, generated at first device
  registration (**SHOULD**).
- The **public key** is the 32-byte Ed25519 key, **MUST** be base64url-encoded
  (RFC 4648 §5, no padding), and **MUST** be stored:
  - in `device.json` (`public_key` JSON key) for the local device, and
  - in the **first entry** of the device's oplog file (`pubKey` field), so
    other devices can obtain it during sync.
- **Encoding migration.** Legacy `device.json` files encode `public_key` as
  standard base64 **with** padding (RFC 4648 §4). On first Phase-1 read, an
  implementation **MUST** detect the legacy form (the value contains `+`,
  `/`, or `=`), decode it, and re-encode as base64url; it **MAY** rewrite the
  file on first write. All wire formats defined here (entries, manifest,
  `trusted_keys.json`) **MUST** use base64url exclusively.
- The **private key** **MUST NOT** be stored in the sync folder or any plain
  file; it **MUST** live in platform secure storage
  (`flutter_secure_storage`). Only the authoring device may produce signatures
  for its `deviceUuid`.
- `deviceUuid` **MUST** remain the identity in HLC keys, `deviceId`, and file
  names.

### 2.2 Signing input

The signature is computed over:

```text
signingInput = canonicalJson(entryWithoutSignature) + documentPath
```

- `entryWithoutSignature` is the entry object **without** `signature`; all
  other keys (including `pubKey`) **MUST** be present exactly as serialized.
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

## 3. Phase 2 — Device authorization manifest

### 3.1 Purpose

Phase 1 binds entries to a key but not to a set of devices. Phase 2 adds an
explicit allow-list.

### 3.2 Manifest file

Stored at `.sync/.manifest.json` (one per vault). **MUST** be a single JSON
object:

```json
{
  "owner_device_uuid": "<owner device uuid>",
  "authorized_devices": [
    {
      "uuid": "<device uuid>",
      "public_key": "<base64url Ed25519 public key>",
      "added_by": "<uuid of the device that authorized this device>",
      "signature": "<base64url Ed25519 signature>"
    }
  ],
  "manifest_signature": "<base64url Ed25519 signature>"
}
```

All keys **MUST** be snake_case (a reader **MUST** reject any other key name
as invalid). Field semantics:

- `owner_device_uuid` — the owning device's `deviceUuid` (**MUST** be
  present).
- `authorized_devices` — the allow-list (**MUST** be present; empty is
  valid). The owner **MAY** be listed; if absent it is implicitly authorized.
  Each record:
  - `uuid` — the authorized `deviceUuid` (**MUST** be unique).
  - `public_key` — its base64url Ed25519 key (§2.1).
  - `added_by` — the `deviceUuid` whose key signs this record; for
    owner-added devices **MUST** equal `owner_device_uuid`.
  - `signature` — Ed25519 over `canonicalJson(recordWithoutSignature)`
    (§2.2), by the `added_by` device.
- `manifest_signature` — Ed25519 over
  `canonicalJson(manifestWithoutSignature)` (§2.2), by the **owner**.

**Key resolution.** The verifier takes the owner's key from the TOFU trust
store (§5.1), i.e. the `pubKey` pinned when the owner's file was first
observed (TOFU runs before the manifest filter, §7). If the owner's key cannot
be resolved, the manifest **MUST** be treated as absent (public, §8.2) — never
a rejection. `added_by` keys resolve the same way (pinned key, or the first
entry of that device's file).

A writer **MUST** produce all signatures; a reader **MUST NOT** accept a
manifest whose `manifest_signature` fails under the owner's key, or a record
whose `signature` fails under its `added_by` key. An invalid manifest
**MUST** be treated as absent (§8.2) and reported.

### 3.3 Authorization check

With a valid manifest, reject every entry whose `deviceId` is not in
`authorized_devices` and is not `owner_device_uuid`. A rejected device's key
**MUST NOT** be added to the trust store (§5.1).

### 3.4 Adding and revoking devices

- **Add**: the owner (or, for future extensions, an already-authorized
  device) signs a new record, appends it, and re-signs the manifest.
- **Revoke**: the owner removes the record and re-signs. Revocation is not
  retroactive — already-signed entries remain in the DAG; the device just
  stops adding new ones.
- The manifest **MAY** be updated while devices are online; each update is an
  atomic file replacement.

---

## 4. Phase 3 — Witness fields

### 4.1 Field

An entry **MAY** carry `seen: Map<String, String>?` — `{deviceId:
lastSeenHlcKey}`.

- The key is another device's `deviceUuid` (never the entry's own).
- The value is the HLC key of the latest entry the author saw from that
  device: `<physicalMs>-<counter>-<deviceId>` — decimal `physicalMs`,
  lowercase-hex `counter` zero-padded to ≥4 chars, `deviceId` as UUID (e.g.
  `1756293123456-0001-7c1e2d3a-…`). This is the same string form as `hlc`/
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

`.noetec/trusted_keys.json` (outside the syncable `.sync` area) maps
`deviceUuid` to the base64url key first observed:

```json
{
  "7c1e2d3a-4b5f-4a6b-8c9d-0e1f2a3b4c5d": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
```

(the value is a base64url 32-byte key — 43 chars, no padding)

### 5.2 TOFU rules

On first observing a device's `pubKey`:

1. Not in `trusted_keys.json` → **MUST** record it (first observation is
   trusted).
2. Present and **equal** → verify normally (§2.4).
3. Present and **different** → key substitution (file-replacement attack, or
   a device that lost its key): **MUST NOT** merge the file's entries,
   **MUST** warn the user and show both keys; the user **MAY** confirm the new
   key (then update `trusted_keys.json` and re-verify), otherwise the stored
   key stays authoritative.

### 5.3 Scope

Per-device local state: **MUST NOT** be synced or shared between vaults;
**MAY** be reset by the user (re-arming first-observation trust).

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
2. **Signature** (§2.4) — on failure, reject entry + rest of chain.
3. **TOFU** (§5.2) — pin or reject the device key.
4. **Manifest filter** (§3.3) — reject non-listed devices (only if a valid
   manifest exists).
5. **HLC drift** (§6.1) — reject/flag future timestamps.
6. **Witness consistency** (§4.3) — report dangling references.

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

### 8.2 Phase 2 — absent manifest

- No `.sync/.manifest.json` → document is **public**: any device with a valid
  key may contribute.
- Present but invalid (malformed or unverifiable) → treated as absent
  (public) and **MUST** be reported. A broken manifest **MUST NOT** lock out
  devices.

### 8.3 Phase 3 — absent `seen`

An entry without `seen` is valid; witness checks apply only to entries that
carry it. Phase-3 devices **SHOULD** include `seen` in every new entry.

### 8.4 Phase 4 — empty TOFU cache and drift

- Empty `trusted_keys.json` → every first observation is trusted and recorded.
- Not adopting drift validation: entries are accepted without the §6.1 check;
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
2. Non-manifest device (§3.3).
3. TOFU key mismatch (§5.2) — show both keys, offer confirmation.
4. HLC drift violation (§6.1).
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

The manifest adds one signature verification per sync cycle (negligible);
`seen` adds at most `O(other devices)` pairs per entry.

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
- Ed25519 — https://ed25519.cr.yp.to/
- Hybrid Logical Clocks (Kulkarni et al.) — https://www.cse.buffalo.edu/tech-reports/2014-04.pdf
- `docs/specs/file-format.md` — page file format (style reference).
