# 0006: Ed25519 Signatures for Sync OpLog Security

## Context

Noetec's sync system (per ADR-0004, layered on top of local-first file storage) exchanges document changes through per-device operation-log files — `.sync/pages/<encoded-path>/<deviceId>.oplog.jsonl` — that live in a shared folder synced by a file service such as Dropbox or WebDAV. The design is deliberately conflict-free at the file level: each device appends only to its own file, and a `OpLogDag` is reconstructed by merging all devices' logs.

The storage layer, however, provides no authenticity guarantees. There is no authentication, no signing, and no per-device authorization — the folder is either shared or not. Concretely:

- `OpLogDag.fromEntries()` today accepts every entry without verifying who actually produced it.
- Any party with read/write access to the shared folder can open another device's `<deviceId>.oplog.jsonl` and append entries that claim that device's identity, or mint a brand-new `<randomId>.oplog.jsonl` to participate in a document uninvited.
- Because entries are the sole record of "what changed and who changed it", a forged or replayed entry silently corrupts the merge result and the attribution of edits.

This ADR captures the decision on **which** cryptographic mechanism to use to make OpLog entries tamper-evident and attributable, and **why** the alternatives were rejected. It is extracted from the broader `docs/SYNC_SECURITY_STRATEGY.md`; the normative field names, serializer changes, and the phased rollout live in a separate spec, and the detailed threat taxonomy is tracked there as well.

## Decision

Sign every `OpLogEntry` with **Ed25519**, one key pair per device:

- **Key generation** happens once, at first run. The **private key** is stored in `flutter_secure_storage` (never in the file system); the **public key** is recorded in `device.json` (and, for the first entry of a log, embedded in that entry itself so the key is discoverable from the data).
- **What is signed** is `canonicalJson(entry) + documentPath` — the entry's canonical JSON serialization **plus** the path of the document it belongs to. Binding `documentPath` into the signature input prevents replaying a valid entry (or its signature) from one document into another.
- **Verification** happens on read: when the DAG is built, each entry's signature is checked against the device's public key. An entry whose signature fails is rejected, and the chain it would extend is treated as untrusted.
- The existing `deviceUuid` is retained for HLC ordering and file naming; the Ed25519 key is an additional authenticity layer, not a replacement for the identifier (see ADR-0003 for the identity model).

This is the minimal, self-contained primitive that closes forgery and provides attribution without introducing any trusted third party or new network topology.

## Status

Proposed.

## Consequences

- Positive: every entry becomes attributable to the device that signed it and tamper-evident — an entry cannot be forged without the corresponding private key, and an entry replayed across documents is detectable.
- Positive: no new infrastructure and no server; the P2P/file-sync model (ADR-0004) is preserved, and offline operation is unaffected (signing/verification are local).
- Positive: the change is backward-compatible — an entry that carries no signature is still accepted (unsigned mode), so existing logs keep working during migration and enforcement can be tightened gradually.
- Negative: a write now costs roughly **~4 ms** of additional Ed25519 signing overhead (≈1 ms → ≈5 ms), and each entry grows by roughly **~40%** (≈500 → ≈700 bytes) to carry the signature.
- Negative: a new runtime dependency, `package:cryptography` (for Ed25519 and SHA-256), is introduced alongside the existing `flutter_secure_storage` for key storage.
- Negative: signing/verification only addresses the authenticity of entries; it does **not** by itself close unauthorized participation, truncation, HLC spoofing, or whole-file substitution — those are addressed by the additional mechanisms in the broader strategy (device authorization, witnesses, TOFU / HLC validation) and are out of scope for this decision.

## Alternatives considered

- **Centralized authentication server** (all entries validated by a server that checks signatures and authorization) — rejected: it contradicts the P2P / file-service sync principle established by ADR-0004 (sync is layered over Dropbox/WebDAV with no app-owned server), introduces a single point of failure, and requires standing up server, database, and monitoring infrastructure that the current architecture deliberately avoids.
- **Blockchain-like consensus** (devices collectively sign and agree on snapshots) — rejected: overkill for a text-document editor; it demands a consensus protocol and places a sustained coordination load on devices for a workload that does not need Byzantine-fault-tolerant agreement.
- **Symmetric shared key** (all devices sign entries with one common secret) — rejected: it provides no attribution — any holder of the key can sign as any device — so it does not solve "who made this change", and it adds the burden of securely distributing the shared secret to every device.
