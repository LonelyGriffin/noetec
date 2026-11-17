# 0006: Ed25519 Signatures for Sync OpLog Security

## Context

The shared sync folder is untrusted transport. Access to it must not let a party
forge another user's contributions or cause unauthenticated changes to enter
merge decisions. Verification must work locally without an authentication server.

## Decision

Sign every OpLog entry with Ed25519 and verify signatures before applying changes.
Bind the signed wire object to its document path so a signature cannot be reused
for a different page path. Preserve signed unknown fields rather than rebuilding
the signing input through a lossy application model.

Private keys remain in protected local storage and are never published to the
shared folder. The [user-key and registry decision](0010-vault-scoped-user-keys-and-device-registry.md)
defines the signing subject and authorization boundary. A valid signature alone
does not authorize participation.

The [sync security contract](../contracts/sync-security-v2.md) defines signing
inputs, encodings, verification, and failure handling. There is no unsigned or
legacy acceptance mode.

## Status

Accepted as the signing primitive of the sync architecture. The detailed sync
contract remains draft; this is not a claim of implementation completion.

## Consequences

- Entries are tamper-evident and attributable to a user-key holder, not provably
  to a physical device.
- Signing and verification work offline without changing the transport topology.
- Key protection, authorization, and compromised-key recovery remain necessary.
- Signatures add computation and storage overhead; they do not provide content
  confidentiality, delivery, freshness, or complete history.

## Alternatives considered

- **Transport access alone** — does not authenticate individual contributions.
- **One symmetric secret for all users** — any holder could forge another user's
  contributions.
- **Mandatory authentication server** — adds infrastructure and online dependence
  that local verification does not require.
- **Collective consensus** — adds coordination and complexity beyond entry
  authenticity and the chosen authorization model.
