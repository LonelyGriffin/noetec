# Noetec Sync Security v2

**Format version: 2. Status: draft.**

This contract defines OpLog signatures, vault users and permissions, signed
device registries, invitations, key rotation, and witness references. The base
OpLog operation semantics and transport delivery are outside its scope.
**MUST**, **MUST NOT**, **SHOULD**, and **MAY** have their RFC 2119 and RFC 8174
meanings.

This format is new. Readers and writers are not required to accept any earlier
Noetec sync or security format. No legacy compatibility or migration behavior
is defined.

## 1. Trust model

The shared sync folder is untrusted: its contents may be read, modified,
deleted, replaced, or delayed. Private keys and local trusted state are outside
this threat model. Private keys MUST remain in secure local storage and MUST NOT
be published to the shared folder or unprotected files.

Every vault has an owner and a vault-specific owner user key. The owner key is
the root of trust. Only signed changes from authorized users and registered
devices may be applied. Missing or invalid security data MUST NOT weaken these
requirements.

Signatures verify signed content, not delivery, freshness, or completeness of
history. Witnesses detect some inconsistent history; they do not restore data
or guarantee detection of a consistent whole-folder rollback. The protocol does
not provide content confidentiality.

## 2. Users, keys, and devices

Each user has one current Ed25519 key pair per vault. Keys MUST NOT be reused
between vaults. The key identifies and authorizes that user only in that vault
and is shared by the user's devices. The owner
user key is the vault root key. The owner authorizes other users by signing
their public keys and permissions.

Devices do not have independent authorization keys. A device has a `deviceId`
and a signed device-registry record. The device ID identifies declared device
streams and does not grant permissions beyond those of its user. A physical
device used by multiple users has a separate device ID for each user.

The identity of an OpLog stream is the ordered pair `(userId, deviceId)`.
`deviceId` is unique only within a user. Public keys are 32-byte Ed25519 keys;
signatures are 64-byte Ed25519 signatures. Both use Base64url without padding
(RFC 4648 §5).

The owner key is established locally when a vault is created and through a
trusted invitation when a user joins. Shared-folder contents MUST NOT
automatically establish or replace it. The trusted owner key is vault-scoped
local state and MUST NOT be synced. Its storage representation is
implementation-defined.

## 3. Bootstrap and invitations

### 3.1. Vault creation

Vault creation establishes the owner user, its vault-specific key, and the
owner's initial active device. The initial user registry and the owner's device
registry are created as signed bootstrap state. A device MUST be active in the
accepted device registry before its entries are accepted.

### 3.2. User invitation

1. The owner creates an individual invitation for one participant.
2. The participant receives it through a QR code and establishes a trusted
   binding to the vault and owner public key.
3. The participant presents a vault-specific user public key and proves
   possession of its private key.
4. The owner confirms the participant and publishes signed authorization with
   the participant's permissions.
5. The participant registers an initial device ID in the participant's signed
   device registry before contributing entries.

An invitation alone does not authorize sync participation. A used or cancelled
invitation MUST NOT authorize another enrollment. QR encoding, invitation
representation, confirmation, request transport, and concurrent-confirmation
handling are implementation-defined subject to these results.

### 3.3. Additional user device

An additional device obtains the user's vault-specific private key and trusted
vault binding through an authorized transfer or recovery procedure. It does not
require new user authorization. The user registers its device ID in the signed
device registry before its entries are accepted. A copied key gives the device
the same user permissions; independent cryptographic device revocation is not
provided.

## 4. Signed entries

### 4.1. Storage and fields

Each device appends only to its own per-page JSONL file:

```text
.sync/pages/<encoded-path>/<userId>--<deviceId>.oplog.jsonl
```

`userId` and `deviceId` in the file name MUST be canonical lowercase UUIDs. The
wire field `userId` identifies the signing user and `device` MUST equal the
file-name `deviceId`. The pair from the path is the stream identity. A parser
MUST reject ambiguous or non-canonical names.

The base OpLog format is outside this contract and does not yet have a
standalone contract. These security extensions add:

| Field | Representation | Presence |
|---|---|---|
| `signature` | Base64url Ed25519 signature | Required on every entry |
| `pubKey` | Base64url user public key | Required on the first entry; absent later |
| `userId` | User UUID | Required on the first entry; absent later |
| `seen` | Object mapping stream IDs to HLC keys (§8) | Optional |

The first entry has no `parent`. Its `pubKey`, `userId`, and `device` identify
the stream. The signing key MUST match an active or historical key authorized
for that user, and the `(userId, deviceId)` pair MUST be active in the accepted
device registry for new entries. Later entries in the stream MUST use the same
user key and device ID. Unsigned entries are rejected.

Historical entries use the authorization in §6, not the requirement for an
active device in the current registry. The path's `userId` MUST match the first
entry's signed `userId`; `device` MUST match the path on every entry.

### 4.2. Signing input

```text
signingInput = canonicalJson(entryWithoutSignature) + UTF8(documentPath)
```

`entryWithoutSignature` is the received wire object with only `signature`
removed, including extension and unknown fields. Absent fields remain absent;
present fields, including null values, remain present. Verification MUST NOT
reconstruct the object through a model that drops or introduces fields.

`documentPath` is the page path relative to the vault root, without its
extension, using `/` separators. Its UTF-8 bytes are appended without a
separator. Vault-specific user keys provide vault authorization isolation; the
vault's technical metadata identifier is not part of the signing input.

`canonicalJson` uses this byte encoding:

- Object keys are sorted lexicographically by the UTF-8 bytes of their
  JSON-escaped, NFC-normalized keys.
- No whitespace is inserted between tokens.
- Strings use UTF-8 and NFC normalization. Only `"` and `\` are escaped;
  control characters are emitted raw, not as `\uXXXX` escapes.
- Arrays retain their order.
- Null is the literal `null`; null-valued members and array items are retained.
- Numbers are integers. Floating-point values, NaN, and infinity are rejected.

Writers sign canonical bytes with the current user key and encode the result in
`signature`. Canonical bytes are not the JSONL serialization.

## 5. User authorization

`.sync/users.json` is one owner-signed JSON object per vault:

```json
{
  "version": 2,
  "revision": "<HLC key>",
  "parent": null,
  "owner_user_id": "<owner UUID>",
  "users": [
    {
      "userId": "<user UUID>",
      "name": "<display name>",
      "publicKey": "<current vault-specific user public key>",
      "historicalKeys": [],
      "permissions": ["<permitted operation>"],
      "updatedAt": "<HLC key>",
      "removedAt": null,
      "signature": "<record signature>"
    }
  ],
  "signature": "<whole-file signature>"
}
```

`userId` values are unique. The owner record MUST exist, its `userId` MUST equal
`owner_user_id`, and its `publicKey` MUST equal the locally trusted owner key.
The owner signs the whole registry and every user record. `name` is a display
name. `permissions` contains only write or administrative permissions; folder
read access is controlled by the transport and is not a cryptographic user
permission. Non-null `removedAt` is a revocation tombstone.

Permission names and their operation mapping are defined by the application
contract. Unknown permissions MUST NOT grant authority. The example uses
illustrative placeholders; it does not define a permission vocabulary.

New contributions require an authorized current user key and an operation
permitted by that user's record. The owner alone changes user authorization in
this version. The owner key is
the local trust root and is not rotated by an ordinary user-registry update;
changing it requires a separate trusted vault procedure.

## 6. User key history and rotation

`historicalKeys` records public keys previously authorized for the user and the
permitted history of their closed streams. Within the owner-signed user record,
each historical-key record binds a public key to unambiguous accepted history
boundaries for each affected page and `(userId, deviceId)` stream. A boundary
MUST identify permitted history, not merely an upper timestamp. Its concrete
representation is not defined by this draft.

On key rotation:

1. The owner authorizes the new current key and records the previous key in
   `historicalKeys`.
2. Every stream written with the previous key is closed at its authorized
   history boundary. Historical authorization MUST remain verifiable from
   owner-authorized state, not depend solely on which entries a reader previously
   saw. The historical key permits only the history identified by those
   boundaries, not other entries with smaller timestamps.
3. New entries MUST use the new current key and a newly registered device ID.
4. Previously accepted entries remain verifiable history; the old key MUST NOT
   create new entries or continue a closed stream.

The accepted rotation record is the authority for key status. Historical
verification state MUST remain available; current authorization uses the new
registry and key. Timestamps alone
do not establish whether an entry was created before rotation. An entry signed
by a historical key outside its permitted history is rejected. The exact
replacement and recovery procedure is implementation-defined but MUST produce
these signed authorization results.

User revocation prohibits new contributions and does not automatically destroy
previously accepted history. Replacement of a compromised user key requires a
verified owner authorization update.

## 7. User device registry

`.sync/devices/<userId>.json` is one user-signed JSON object per authorized user:

```json
{
  "version": 2,
  "revision": "<HLC key>",
  "parent": null,
  "userId": "<user UUID>",
  "devices": [
    {
      "deviceId": "<device UUID>",
      "name": "<display name>",
      "addedAt": "<HLC key>",
      "updatedAt": "<HLC key>",
      "removedAt": null,
      "signature": "<record signature>"
    }
  ],
  "signature": "<whole-file signature>"
}
```

The file's `userId` MUST equal the UUID in its name. Device IDs are unique
within that user. The registry is signed by the current user key; each record
and the whole file have the required signatures. An empty device array is valid.

The registry is a strict allowlist. New contributions MUST NOT be applied unless
their `(userId, deviceId)` pair is present and active (`removedAt: null`) in the
accepted verified registry. Missing, invalid, unknown, or revoked device
authorization MUST NOT be accepted automatically. A missing or invalid
required registry suspends acceptance of new contributions; local data and
unsynced changes are preserved.

The registry identifies declared devices and streams, not physical device
origin. Any holder of a current user key can declare a device and sign as it.
Revoking a device ID does not independently revoke a holder of the user key.

### 7.1. Registry signatures and updates

For both registries, each record signature covers
`canonicalJson(recordWithoutSignature)`. The whole-file signature covers
`canonicalJson(fileWithoutSignature)`, retaining record signatures. Invalid
required signatures invalidate the registry. The owner signs user authorization;
the current user key signs its device registry.

`parent` identifies the preceding registry revision, or is null for an initial
revision. Updates advance `revision` and `parent`. Older state MUST NOT silently
replace accepted newer authorization. Ambiguous or conflicting updates MUST NOT
automatically grant authority or undo revocation. Resolution and publication
mechanisms are implementation-defined and MUST preserve required signer authority.

User or device revocation MUST NOT automatically destroy previously accepted
history. Historical authorization is distinct from permission for new
contributions. Preservation of history does not authorize new writes under a
revoked identity.

## 8. History and witnesses

OpLog parent references identify preceding history. Readers MUST check those
relationships before applying dependent changes.

### 8.1. Witness representation

`seen` maps a canonical stream ID, `<userId>--<deviceId>`, to the latest HLC key
observed from it:

```json
{"seen": {"7c1e2d3a-4b5f-4a6b-8c9d-0e1f2a3b4c5d--9a0b1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d": "1756293123456-0001-7c9d2e1a"}}
```

HLC keys have the form `<physicalMs>-<counter>-<nodeId>`: decimal Unix
milliseconds, a lowercase hexadecimal counter padded to at least four digits,
and the first eight hexadecimal digits of the hyphen-free device UUID.
HLC ordering compares
numeric physical time, numeric counter, then the canonical stream identity
`(userId, deviceId)`. The textual `nodeId` is not sufficient as a final tie-break
and MUST NOT replace the full pair.

A stream MUST NOT witness itself. A reference MUST identify the referenced
stream's node ID and be non-decreasing across the author's stream. Writers
SHOULD include the latest observed heads of other streams. Null or empty `seen`
is omitted on write; absent and empty are equivalent on read.

### 8.2. Witness policy

Only entries passing signature, trust, authorization, and drift checks supply
witness references. Evidence is evaluated over signature-verified entries in
the referenced stream, including entries excluded by authorization or drift.

A dangling reference exists when the referenced stream file exists but contains
no verified entry at or after the referenced HLC. A dangling reference MUST be
reported, and the referenced remote stream MUST be excluded from that page's
DAG and merge decisions. The referencing stream remains eligible. A dangling
reference to the local stream MUST be reported without excluding the local
stream; the page MUST be flagged instead.

The reference reports inconsistency, not proof of an attack. An authorized user
can fabricate references and cause remote-stream exclusion; this policy does
not protect availability against malicious authorized participants. Witness
exclusion does not invalidate the referencing signature.

A missing referenced file MAY be ignored. A malformed reference MUST be reported
and ignored; it does not by itself reject the referencing entry. Witnesses detect
some inconsistent truncation or replacement, not exact historical content,
delivery, or completeness. Consistent whole-folder rollback and unwitnessed
truncation can remain undetected.

## 9. Verification and failures

Before applying entries:

1. Verify the user registry under the trusted owner key.
2. Verify each required user device registry under its authorized current user
   key.
3. Read each device stream in order; verify path, structure, key history, and
   signatures.
4. Check the user, `(userId, deviceId)` pair, and operation permissions.
5. Apply HLC drift validation to remote entries (§9.1).
6. Evaluate witnesses (§8) and parent relationships before building applicable
   history.

A malformed or signature-unverifiable entry rejects that entry and the remaining
suffix of its device stream. Rejected changes MUST NOT be applied or influence
merge decisions; rejected entries supply no witness references.

Verification failures MUST be reported with the affected source and reason.
Rejection MUST NOT rewrite, truncate, or delete source files. Unknown signed
fields MUST be retained unchanged when preserving an entry; incompatible wire
changes require a new version.

### 9.1. HLC drift

Remote entries MUST satisfy:

```text
entry.hlc.physicalMs <= localTime + maxDrift
```

`localTime` is the reader's wall clock in Unix milliseconds at read time.
`maxDrift` defaults to 60 000 ms, may be increased, and MUST NOT be configured
below that default. It is vault-scoped local state and MUST NOT be synced.

The first entry above the bound and its remaining device-stream suffix are
excluded before applying changes. Excluded entries MUST NOT advance the local
HLC or supply witness references. The check is re-evaluated on reads; passing it
removes only the drift exclusion, not other verification requirements. The
local device's own stream is exempt. Registry timestamps are not covered by
this check.

## References

- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
  [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174)
- [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648)
- [Ed25519](https://ed25519.cr.yp.to/)
- [Hybrid Logical Clocks](https://www.cse.buffalo.edu/tech-reports/2014-04.pdf)
- [Sync v2 architectural decision](../decisions/0010-vault-scoped-user-keys-and-device-registry.md)
