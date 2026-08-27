# Noetec Sync Security Extensions

**Format version: 1 (draft)**

This document is the normative specification of the security extensions to the
Noetec sync operation log (OpLog) entry format: cryptographic signatures,
device authorization, witness references, and key-trust validation. It is a
contract: implementations (parsers, serializers, sync engines, external tools)
**MUST** conform to this document. If an implementation diverges from this
specification, that is a bug in the implementation, not in this document.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
in this document are to be interpreted as described in RFC 2119.

The base OpLog entry format (`version`, `hlc`, `parent`, `parentB`, `type`,
`blockOps`, `fileOp`, `fileHash`, `deviceId`), the HLC key format, and the
on-disk layout of device oplog files are defined by the existing codebase;
this specification extends that format and **MUST** be read against it. The
page file format specification (`docs/specs/file-format.md`) is the style and
format reference for this document; where the two documents address the same
concept, this document is authoritative for the sync security extensions.

The extensions are defined in four phases:

- **Phase 1 — Cryptographic signatures** (mandatory target): every entry is
  signed with the authoring device's Ed25519 key.
- **Phase 2 — Device authorization manifest**: documents may declare the set
  of devices allowed to contribute entries.
- **Phase 3 — Witness fields** (`seen`): every entry records the latest
  entries it has observed from other devices, making history truncation
  detectable.
- **Phase 4 — TOFU and HLC drift validation**: local trust-on-first-use key
  pinning and rejection of physically implausible timestamps.

All four phases are **backward compatible** with unsigned, legacy oplog data
(see §8).

---

## 1. Overview

### 1.1 Storage layout

The sync subsystem stores one append-only JSONL file per device per page:

```text
.sync/pages/<encoded-path>/<deviceId>.oplog.jsonl
```

- Each device appends entries **only** to its own file; this keeps
  file-system-level sync (WebDAV/Dropbox) conflict-free and moves all
  conflict resolution to the logical (DAG) level.
- The device identifier in the file name is the device's `deviceUuid` — the
  same identifier carried in `deviceId` on entries and in HLC keys. Security
  extensions **MUST NOT** change this naming scheme.
- The document's owner device identity (including its public key) is stored
  in `.noetec/device.json` at the vault root.
- This specification additionally defines two files: `.sync/.manifest.json`
  (Phase 2) and `.noetec/trusted_keys.json` (Phase 4).

### 1.2 Entry format, extended

The security extensions add the following fields to an oplog entry. All are
new keys in the serialized entry; existing keys are unchanged:

| Field       | Type             | Phase | Present | Description                                             |
| ----------- | ---------------- | ----- | ------- | ------------------------------------------------------- |
| `signature` | string           | 1     | MUST*   | Ed25519 signature over the entry, base64url-encoded.   |
| `pubKey`    | string or null   | 1     | first entry of a device file MUST; all others MUST be absent | Base64url-encoded Ed25519 public key of the authoring device. |
| `seen`      | map or null      | 3     | SHOULD for new entries | Witness references: `{deviceId: lastSeenHlcKey}`.      |

\* Mandatory for entries produced by implementations that have adopted
Phase 1. Entries **without** `signature` are legacy entries and are accepted
during migration (see §8.1).

### 1.3 Threat model

The extensions defend against the following attacker: an adversary with
**read/write access to the shared sync folder** (for example, through a
compromised or overly broad sync share), who can read, append to, truncate,
or replace oplog files and the manifest, but who does **not** possess the
victim's private key.

Out of scope are: an adversary with access to the victim device's secure key
storage (the private key itself), and an adversary who can persistently
tamper with *all* devices in a document at once (the first legitimate
observation of a key is always trusted — see §5.2).

---

## 2. Phase 1 — Cryptographic signatures

### 2.1 Keys

- The signature algorithm **MUST** be Ed25519.
- Each device holds exactly one key pair for a vault. The key pair **SHOULD**
  be generated at first device registration for that vault.
- The **public key** is the 32-byte Ed25519 public key, **MUST** be encoded
  as base64url (RFC 4648, §5, no padding), and **MUST** be stored:
  - in the vault's `device.json` (`publicKey` field) for the local device, and
  - in the **first entry** of the device's oplog file (`pubKey` field), so
    that other devices can obtain it during sync.
- The **private key** **MUST NOT** be stored in the sync folder, in the
  vault directory, or in any plain file. It **MUST** be kept in the
  platform secure key storage (`flutter_secure_storage`). This is an
  implementation detail; this specification requires only that the private
  key is never written to any syncable or world-readable location and that
  only the authoring device can produce signatures for its `deviceUuid`.
- A device's `deviceUuid` **MUST** remain the identity used in HLC keys,
  `deviceId` fields, and file names, as before. Implementations **MAY**
  additionally compute a key fingerprint (`SHA-256` of the raw public key
  bytes) for display or diagnostics, but **MUST NOT** use it in place of the
  `deviceUuid` in any wire format.

### 2.2 Signing input

An entry's signature **MUST** be computed over the **signing input**:

```text
signingInput = canonicalJson(entryWithoutSignature) + documentPath
```

where:

1. `entryWithoutSignature` is the entry's JSON object **without** the
   `signature` key (all other keys, including `pubKey`, **MUST** be present
   in the object exactly as they appear in the serialized entry), and
2. `documentPath` is the page's path **relative to the vault root**, without
   the file extension, using `/` as the path separator (e.g. `notes/ideas`).

`canonicalJson(obj)` **MUST** be defined as:

- a JSON object serialized with **keys sorted lexicographically** (UTF-8 code
  point order);
- **no whitespace** other than the structural separators (`,` and `:`);
- strings encoded as UTF-8;
- arrays serialized in their stored order (order is significant);
- `null`-valued keys **MAY** be omitted from the object (and therefore from
  the signature input); implementations that omit them on write **MUST**
  omit them on verify.

`documentPath` is appended directly to the JSON text (no separator).

### 2.3 Signature rules

- On **write**, an implementing device **MUST** sign `signingInput` with its
  Ed25519 private key and store the 64-byte signature, base64url-encoded
  (no padding), in the entry's `signature` field.
- The `pubKey` field **MUST** be present on the **first entry** of a device's
  oplog file (the entry with no `parent`), **MUST** equal the device's
  public key in `device.json`, and **MUST NOT** be present on any subsequent
  entry of that file.
- Entries from the same device in **different** documents are signed with
  the same key pair; the key travels with the first entry of each file.

### 2.4 Verification rules

When building the oplog DAG from device files, an implementation **MUST**
verify signatures as follows, processing each device file from its first
entry to its last:

1. **First entry**: **MUST** contain a non-null `pubKey`. A first entry
   without `pubKey` is treated as a legacy unsigned entry (see §8.1) and does
   not by itself invalidate the file.
2. **Every entry with a `signature`** **MUST** be verified: the signature
   **MUST** be a valid Ed25519 signature of `signingInput` (§2.2) under the
   device's public key (the `pubKey` from the file's first entry, or, for the
   local device, the key from `device.json`).
3. **Chain rejection on invalid signature.** If an entry's signature fails
   verification (or the entry is structurally malformed in a way that
   prevents verification), the implementation **MUST** reject that entry and
   **MUST** reject **all subsequent entries in the same device file**
   (everything after the first invalid entry, by file order). Earlier valid
   entries remain part of the DAG.
4. **Re-keying.** A change of public key is **MUST NOT** be accepted
   silently: if a later entry of a device file (or the first entry of a
   previously unseen file) carries a public key that differs from the one the
   device has been observed with before, the implementation **MUST** apply the
   TOFU rules of §5.2.
5. Entries that are legacy (no `signature`) do not start a chain rejection;
   a legacy entry followed by signed entries is accepted as long as the
   signed entries verify (see §8.1).
6. Rejected entries **MUST NOT** contribute to the DAG, to merge decisions,
   or witness state, and **MUST** be reported to the user (see §9).

---

## 3. Phase 2 — Device authorization manifest

### 3.1 Purpose

Phase 1 binds every entry to a device key, but does not restrict *which*
devices may contribute to a document. Phase 2 adds an explicit allow-list.

### 3.2 Manifest file

The manifest is stored at `.sync/.manifest.json` at the vault root (i.e. one
manifest per vault, inside the syncable area). It **MUST** be a single JSON
object with exactly the following shape:

```json
{
  "owner_device_uuid": "<uuid of the document owner's device>",
  "authorized_devices": [
    {
      "uuid": "<device uuid>",
      "pubKey": "<base64url Ed25519 public key>",
      "added_by": "<device uuid of the device that authorized this device>",
      "signature": "<base64url Ed25519 signature>"
    }
  ],
  "manifest_signature": "<base64url Ed25519 signature>"
}
```

Field semantics:

- `owner_device_uuid` — the `deviceUuid` of the device that owns the vault.
  **MUST** be present.
- `authorized_devices` — an array of authorization records, one per
  authorized device (the owner **MAY** be listed; if absent, the owner is
  implicitly authorized). **MUST** be present (an empty array is valid).
  Each record:
  - `uuid` — the `deviceUuid` of the authorized device. **MUST** be unique
    within the array.
  - `pubKey` — that device's Ed25519 public key, base64url, per §2.1.
  - `added_by` — the `deviceUuid` of the device whose key signed this
    record. For devices added by the owner, **MUST** equal
    `owner_device_uuid`.
  - `signature` — an Ed25519 signature over `canonicalJson(recordWithoutSignature)`
    (the record object without its own `signature` key, canonicalized per
    §2.2), produced by the `added_by` device's private key.
- `manifest_signature` — an Ed25519 signature, produced by the **owner's**
  private key, over `canonicalJson(manifestWithoutSignature)` — the manifest
  object without its own `manifest_signature` key, canonicalized per §2.2.

An implementation writing the manifest **MUST** produce all signatures; an
implementation **MUST NOT** accept a manifest whose `manifest_signature` does
not verify under the owner's public key, and **MUST NOT** accept an
authorization record whose `signature` does not verify under the key of the
`added_by` device. A manifest that fails verification **MUST** be treated as
absent (see §8.2) and **MUST** be reported to the user.

### 3.3 Authorization check

When building the oplog DAG, if a valid manifest exists for the vault, the
implementation **MUST** reject every entry whose `deviceId` does not appear
in `authorized_devices` (or equals `owner_device_uuid`). The public key of a
rejected device's entries **MUST NOT** be added to the local trust store
(§5.1) as a side effect of observing rejected entries.

### 3.4 Adding and revoking devices

- Adding a device: the owner (or a device already in the manifest, for
  future extensions) signs a new authorization record with its private key,
  appends it to `authorized_devices`, and re-signs the whole manifest.
- Removing a device: the owner removes the record and re-signs the manifest.
  Revocation is **not** retroactive: entries already present in a removed
  device's oplog file that are validly signed remain part of the DAG; the
  device simply stops being able to add new entries.
- The manifest **MAY** be updated while devices are online; each update is an
  atomic replacement of the file.

---

## 4. Phase 3 — Witness fields

### 4.1 Field

Each oplog entry **MAY** carry a `seen` field:

```text
seen: Map<String, String>?    // {deviceId: lastSeenHlcKey}
```

- The key is another device's `deviceUuid` (never the entry's own device).
- The value is the HLC key (the string form `physicalMs-counter-deviceId`
  used in `hlc`/`parent` fields) of the **latest entry that the authoring
  device has seen from that device** at the moment the entry is written.

### 4.2 Population

- When an implementing device creates an entry, it **SHOULD** include a
  `seen` field mapping every *other* device of the document to the latest HLC
  key it has observed from that device.
- A device **MUST NOT** list itself in its own `seen` field.
- The `seen` values for a given authoring device **MUST** be non-decreasing
  over that device's file (by HLC key order): an entry's `seen[d]` **MUST**
  be HLC-ordered at or after the previous entry's `seen[d]`, or absent.

### 4.3 Verification (truncation detection)

The witness graph provides cross-device references that survive in files the
attacker does not control, making truncation of *another* device's file
detectable:

- After building the DAG, the implementation **SHOULD** check, for each entry
  that carries `seen`: for every `(d, hlcKey)` in that entry's `seen`, if the
  device `d`'s file exists but contains **no entry with an HLC key HLC-ordered
  at or after `hlcKey`**, the reference is **dangling**.
- A dangling reference indicates that the referenced device's file was
  truncated after the referring entry was written (a truncation attack, or
  an unrecoverable sync corruption). The implementation **MUST NOT** silently
  ignore dangling references: it **MUST** report the affected file and the
  dangling reference(s) to the user, and **SHOULD** treat the truncated file's
  entries as untrusted (see §9 for the required user-facing behavior).
- A `seen` reference to a device whose file does not exist at all is **not**
  dangling (the device may simply have been removed from the sync share);
  such references **MAY** be ignored.

---

## 5. Phase 4a — Trust-on-first-use (TOFU)

### 5.1 Trusted keys file

The local TOFU cache is stored at `.noetec/trusted_keys.json` (outside the
syncable `.sync` area). It **MUST** be a JSON object mapping `deviceUuid` to
the base64url Ed25519 public key first observed for that device:

```json
{
  "7c1e2d3a-4b5f-4a6b-8c9d-0e1f2a3b4c5d": "dGVzdHB1YmtleQ=="
}
```

### 5.2 TOFU rules

When the implementation observes an oplog file for a device for the first
time (or sees a `pubKey` it has not seen for that device):

1. If the device is **not present** in `trusted_keys.json`, the implementation
   **MUST** record the observed `pubKey` for that `deviceUuid` (the first
   observation is trusted).
2. If the device **is present** and the observed `pubKey` **equals** the
   stored key, verification proceeds normally (§2.4).
3. If the device **is present** and the observed `pubKey` **differs** from
   the stored key, the implementation **MUST** treat this as a key
   substitution (a file-replacement attack, or a legitimate device that
   lost its key):
   - the conflicting file's entries **MUST NOT** be merged into the DAG;
   - the implementation **MUST** warn the user and present the two keys;
   - the user **MAY** explicitly confirm the new key, in which case the
     implementation **MUST** update `trusted_keys.json` and re-verify the
     file's entries; without confirmation the stored key remains authoritative.

TOFU protects against whole-file replacement (threat 6, §10): an attacker
who replaces `<victim>.oplog.jsonl` with a file signed by the attacker's
key will be rejected, because the first entry's `pubKey` will not match the
key stored in `trusted_keys.json`.

### 5.3 Scope

`trusted_keys.json` is per-device, local state. It **MUST NOT** be synced,
**MUST NOT** be shared between vaults, and **MAY** be reset by the user (a
reset re-arms first-observation trust for all devices).

---

## 6. Phase 4b — HLC drift validation

### 6.1 Rule

Hybrid Logical Clock timestamps can be spoofed: an attacker who cannot
forge signatures may still write entries whose `hlc.physicalMs` lies far in
the future, biasing merge ordering in their favor (the HLC key orders by
`physicalMs` first).

When reading **other** devices' entries, the implementation **MUST** check:

```text
entry.hlc.physicalMs <= localTime + maxDrift
```

where `localTime` is the local wall clock in milliseconds since the Unix
epoch and `maxDrift` **SHOULD** default to 60 000 ms (60 seconds) and **MAY**
be configured to a larger value.

- An entry with `physicalMs` within the bound is accepted as normal.
- An entry with `physicalMs` **greater** than `localTime + maxDrift`
  **MUST** be treated as suspicious: the implementation **MUST NOT** apply it
  as a merge result without user awareness, **MUST** report it, and **MAY**
  reject it outright. A common policy **SHOULD** be: reject entries that
  outrun the local clock by more than `maxDrift`, and surface them to the
  user in the sync status.
- Entries with `physicalMs` far in the *past* are valid (a slow device is
  not an attack); no lower bound is imposed.
- The check **MUST** be applied to entries of *other* devices only; a device
  **MUST NOT** reject its own entries on this check.
- Suspicious entries **MUST** be logged (via `package:logging`, never
  `print`) for manual analysis.

---

## 7. Verification pipeline (normative order)

When building the oplog DAG from a document's device files, the checks of the
adopted phases **MUST** be applied in the following order; a failure at any
step stops processing of the affected entries:

1. **Parse** each file line by line; structurally invalid JSON lines are
   rejected in place (they do not, by themselves, invalidate later lines
   that parse cleanly).
2. **Signature verification** (Phase 1, §2.4): verify each entry; on failure,
   reject the entry and the rest of that file's chain.
3. **TOFU check** (Phase 4a, §5.2): pin or reject the device's public key.
4. **Manifest filter** (Phase 2, §3.3): reject entries from devices not in
   the manifest (only if a valid manifest exists).
5. **HLC drift check** (Phase 4b, §6.1): reject or flag entries with
   physically impossible future timestamps.
6. **Witness consistency check** (Phase 3, §4.3): detect dangling references
   and report truncation.

Checks are applied per file and per entry as specified; phases that have not
been adopted by an implementation are simply absent from the pipeline.

---

## 8. Backward compatibility

All extensions are additive and **MUST** remain backward compatible so that
existing unsigned oplog data keeps working:

### 8.1 Phase 1 — unsigned entries

- An entry without a `signature` field is a **legacy entry** and **MUST** be
  accepted as valid during the migration period.
- A device file may contain any mix of legacy (unsigned) and signed entries;
  the first signed entry after a run of legacy entries is verified against
  the `pubKey` from the file's first entry (or, failing that, from the local
  trust store / `device.json` if it is the local device).
- An implementation **SHOULD** display a warning when a document contains
  legacy entries, and **MAY** be configured (per vault) to reject unsigned
  entries once all participating devices have migrated. Rejecting unsigned
  entries is an opt-in hardening mode; the default **MUST** remain
  acceptance.
- A device that adopts Phase 1 **MUST** sign every entry it writes from then
  on; it **MUST NOT** write new unsigned entries.

### 8.2 Phase 2 — absent manifest

- If `.sync/.manifest.json` does not exist, the document is **public**: any
  device with a valid key for its file may contribute entries.
- If the file exists but is invalid (malformed JSON, or a signature that does
  not verify), it **MUST** be treated as absent (document is public) and the
  condition **MUST** be reported to the user. A broken manifest **MUST NOT**
  lock out all devices.

### 8.3 Phase 3 — absent `seen`

- An entry without a `seen` field is valid. Witness checks apply only to
  entries that carry `seen`.
- Devices that adopt Phase 3 **SHOULD** include `seen` in every new entry.

### 8.4 Phase 4 — empty TOFU cache and drift

- If `trusted_keys.json` is absent or empty, every first observation is
  trusted and recorded (no check possible yet).
- If a deployment does not adopt HLC drift validation, entries are accepted
  without the §6.1 check; adopting the check later **MUST NOT** invalidate
  already-merged entries (the check applies to newly observed entries).

### 8.5 Serialization compatibility

- New fields (`signature`, `pubKey`, `seen`) are **additional JSON keys** in
  the entry object. An implementation that does not know a key **MUST**
  ignore it on read and **MUST** preserve it on round-trip whenever feasible.
- The entry's `version` field is not changed by these extensions in format
  version 1; a future, incompatible change to any rule in this document
  **MUST** bump the entry version and be published as a new version of this
  specification (mirroring the versioning policy of the page file format
  spec).

---

## 9. Reporting to the user

Implementations **MUST** surface security events rather than failing
silently:

1. A signature that failed verification (§2.4).
2. An entry from a device not in the manifest (§3.3).
3. A TOFU key mismatch (§5.2) — with both keys shown and a confirmation
   prompt.
4. An HLC drift violation (§6.1).
5. Dangling witness references (§4.3) — naming the file and the referenced
   HLC key.
6. Presence of legacy unsigned entries in a migrated document (§8.1).

All of these events **MUST** be recorded in the application log via
`package:logging`.

---

## 10. Threat coverage matrix

Coverage of the threat model (§1.3) by phase. Legend: ✅ fully covered,
⚠️ partially covered, ❌ not covered.

| # | Threat | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|---|---|---|---|---|---|
| 1 | Entry forgery (appending entries under a victim's `deviceId`) | ✅ | ✅ | ✅ | ✅ |
| 2 | Unauthorized device participation (new device injecting entries) | ❌ | ✅ | ✅ | ✅ |
| 3 | History truncation (rolling back another device's file) | ⚠️ | ⚠️ | ✅ | ✅ |
| 4 | Replay attack (reusing a valid signature from another document) | ❌ | ❌ | ❌ | ✅ |
| 5 | HLC spoofing (future-dating `physicalMs` to win merges) | ❌ | ❌ | ❌ | ✅ |
| 6 | Whole-file replacement (attacker's file under the victim's name) | ❌ | ❌ | ❌ | ✅ |

Notes:

- Threat 1 is closed by Phase 1 alone: without the private key, an attacker
  cannot produce a valid `signature` for the victim's file. Phases 2–4 keep
  it closed.
- Threat 3 is only partially detected by Phase 1: truncation of the *last*
  entries may be invisible while the surviving chain still verifies; witness
  cross-references (Phase 3) make it detectable via dangling references.
- Threat 4 is covered by the `documentPath` component of the signing input
  (§2.2): a signature copied from one document does not verify in another.
  Phase 4 is listed as the covering phase because replay protection is only
  *enforced* once TOFU pins which key is expected per document/device.
- Threat 6 (whole-file replacement) is closed by TOFU (§5.2): the replaced
  file's first-entry key does not match the pinned key.

---

## 11. Performance overhead (estimates)

Estimates on a mid-range mobile device, measured against the baseline
unsigned pipeline (values are order-of-magnitude guidance, not guarantees):

| Operation | Without signatures | With signatures (Phase 1) | Overhead |
|---|---|---|---|
| Write one entry | ~1 ms | ~5 ms (one Ed25519 sign) | +4 ms per entry |
| Read/verify 100 entries | ~10 ms | ~50 ms (100 verifications) | +40 ms |
| Entry size on disk | ~500 bytes | ~700 bytes (`signature`, and `pubKey` in the first entry) | ≈ +40% |

Guidance for implementations:

- **Incremental verification (SHOULD).** Cache verification results per entry
  (keyed by HLC key) and verify only newly appended lines during sync;
  re-verifying a whole file on every poll is unnecessary.
- **Lazy verification (MAY).** Verify only when building the DAG, not on
  every file read for display purposes.
- **Batch signing (MAY, not in format version 1).** Signing a batch of
  entries with a single Merkle-root signature reduces storage but
  complicates verification and chain rejection; it is out of scope for
  format version 1 and **MUST NOT** be mixed with per-entry signatures in
  the same file without a spec change.

The manifest (§3) adds one signature verification per sync cycle per vault,
which is negligible. The `seen` map (§4) adds at most
`O(other devices)` string pairs per entry; for a two-device document the
overhead is one key-value pair per entry.

---

## 12. Out of scope

This specification is a contract for format and verification rules only. The
following are **out of scope** and are addressed elsewhere:

- ADR-level decision rationale and the rejected alternatives (centralized
  authentication server, consensus-based collective signing, shared-secret
  symmetric signing) — see the sync security decision record.
- Migration plans, rollout sequencing, and test plans — these belong to the
  implementation tasks.
- File-access mechanics on specific platforms (macOS secure bookmarks,
  Android SAF) — these constrain *where* keys may be stored, not *what* the
  format is.
- Encryption of entry content. These extensions provide integrity,
  attribution, and authorization; entries remain readable by anyone with
  access to the sync folder. Confidentiality is a separate concern.

---

## 13. References

- RFC 2119 — Key words for use in RFCs to Indicate Requirement Levels.
- Ed25519 signature algorithm (Bernstein et al.) — https://ed25519.cr.yp.to/
- Hybrid Logical Clocks (Kulkarni et al.) — https://www.cse.buffalo.edu/tech-reports/2014-04.pdf
- CRDT theory — https://crdt.tech/
- Trust-on-first-use — https://en.wikipedia.org/wiki/Trust_on_first_use
- `docs/specs/file-format.md` — Noetec page file format (style and format reference).
