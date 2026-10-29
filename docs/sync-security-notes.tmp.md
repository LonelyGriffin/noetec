# Sync security — temporary extracted notes

**Status: temporary, non-normative; pending manual review.**

Material extracted from [the sync security contract](contracts/sync-security.md) to separate rollout and
implementation notes from the security contract. This file is neither an
approved implementation plan nor a technical guide. Statements about code and
performance are preserved from the source and have not been revalidated.
Existing ADRs remain in `docs/decisions/`; this file does not replace or
duplicate them.

## Original rollout grouping

The source described the extensions as four phases:

- **Phase 1 — Signatures** (mandatory): every entry is signed with the
  authoring device's Ed25519 key.
- **Phase 2 — User & device registries**: per-user device registries and an
  owner-signed user registry.
- **Phase 3 — Witness fields** (`seen`): each entry records the latest entries
  it observed from other devices, making truncation detectable.
- **Phase 4 — TOFU and HLC drift validation**: trust-on-first-use key pinning
  and rejection of implausible timestamps.

These labels still identify compatibility groups in the source contract;
they do not establish a current implementation schedule or completion status.

## Implementation references from the source

- The base OpLog entry format, HLC key format, and device-file layout were
  delegated to the existing codebase, specifically
  `lib/systems/oplog_system/oplog_serializer.dart`. A standalone base-format
  contract remains outside the source document.
- The device-key generator (`lib/service/crypto_service.dart`) was described
  as still emitting padded standard base64 via `base64Encode`. The rules for
  accepting legacy encodings remain in the contract (§2.1).
- The OLPC Canonical JSON implementation cited was the `canonical_json` Dart
  package, v1.1.3. The canonical encoding rules remain in the contract (§2.2).
- The hyphen-free 8-hex HLC node identifier was linked to
  `DeviceIdentity.truncatedDeviceId` (§4.1).
- The read-time wall clock expression was
  `DateTime.now().millisecondsSinceEpoch` (§6).

## Performance overhead (original estimates)

Order-of-magnitude guidance on a mid-range mobile device; no benchmark
methodology or measurements were supplied in the source:

| Operation | Without signatures | With signatures (Phase 1) | Overhead |
|---|---|---|---|
| Write one entry | ~1 ms | ~5 ms | +4 ms |
| Read/verify 100 entries | ~10 ms | ~50 ms | +40 ms |
| Entry size | ~500 B | ~700 B | ≈ +40% |

The original optimization suggestions were:

- **Incremental verification (originally SHOULD):** cache per-entry results
  (keyed by HLC key) and verify only new lines.
- **Lazy verification (originally MAY):** verify only when building the DAG.
- **Batch signing (originally MAY, not in v1):** possible future Merkle-root
  signing. The v1 prohibition on mixing it with per-entry signatures remains
  in the contract (§11).

Additional original estimates:

- **Registries:** a small, constant number of signature verifications per sync
  cycle — negligible.
- **`seen`:** at most `O(other devices)` pairs per entry — roughly 75 bytes per
  referenced device (full UUID + HLC key + JSON syntax), i.e. on a ≈700-byte
  signed entry ≈ +10% with 2 devices, ≈ +35% with 4 and ≈ +85% with 10. Its
  verification costs one extra `O(entries)` pass per device file plus
  `O(references)` comparisons per document.
- **§6 drift validation:** one integer comparison per entry and rejecting a
  suffix — negligible.

## Separate hardening work noted in the source

Registry `revision` keys are signature-protected but are not subjected to the
OpLog drift check (§6). The source noted that the local device adopts a
registry revision into its own clock (`Hlc.receive`). A future-dated revision
signed by an authorized identity key can therefore push the local clock
forward and make this device's own entries look drifted to its peers.
Hardening that path was identified as a separate task.
