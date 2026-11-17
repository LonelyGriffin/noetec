# 0010: Vault-Scoped User Keys and Signed Device Registries

## Context

A vault can have several users, each using several devices. A physical device can
serve multiple users. Ownership and permissions must belong to users, not
machines, while device streams still need explicit registration and attribution.

The authorization subject is the user; a device ID labels a declared stream, not
an independent cryptographic principal. All devices holding a user's vault key
act with that user's authority.

## Decision

- Each user has one Ed25519 key pair per vault, shared by that user's devices.
  Keys are vault-specific; a key for one vault MUST NOT be reused in another.
- The owner's user key is the vault's root of trust. The owner signs user
  authorization, including public keys and permissions. There is no public
  participation mode. Replacing the trusted owner key requires a separate trusted
  vault procedure, not an ordinary user-registry update.
- User keys sign OpLog entries and their own device registries. There are no
  device keys or device-key certificates.
- An OpLog stream is identified by `(userId, deviceId)`. The pair is encoded in
  the per-page file name. Device IDs are unique within a user, and a physical
  device used by several users has a separate registered ID for each.
- A signed device registry remains mandatory for each contributing user. New
  contributions require a registered, active device ID under the signing user;
  unknown, revoked, or unverifiable device authorization is not accepted.
- Device IDs identify declared devices and per-page streams, not independent
  cryptographic identities. A holder of a user key can sign as any of that user's
  devices and update its registry.
- An individual QR invitation establishes trust in the vault and owner key. The
  owner confirms a new user's key and permissions. Additional devices obtain the
  existing user's private key and trusted vault binding through protected
  transfer or recovery, then are registered by that user without new owner
  approval.
- All devices holding the same user key have the same user permissions. Device
  registration does not provide independent cryptographic device revocation.
- Key rotation records historical keys and closes their existing streams at
  explicit accepted history boundaries per page and stream, not by timestamp
  cutoff. Historical entries remain verifiable from owner-authorized state; new
  entries require the new key and newly registered device IDs.
- Witness references follow [ADR-0009](0009-witness-truncation-detection.md): a
  dangling reference to a remote stream excludes that stream from the page DAG,
  the local stream is retained, and the page is flagged. Witnesses detect some
  inconsistent history; they do not guarantee freshness, completeness, or
  protection against a consistent whole-folder rollback.
- This is a new sync format with no legacy reading, compatibility, migration, or
  data-preserving transition requirement.

Wire structures and verification rules are defined in the
[sync security v2 contract](../contracts/sync-security-v2.md). Key transfer,
backup, recovery, invitation transport, historical-boundary representation, and
the permission vocabulary are not specified by this ADR.

## Status

Accepted, 2026-11-14. This records the architectural decision, not implementation
completion or approval of every detail in the draft contract.

## Consequences

- Fewer secrets and verification layers; the same backed-up user key supports
  multiple devices and recovery.
- Separate vault keys isolate credentials and authority between vaults. Private
  keys and any shared recovery secrets still require protection.
- Signed registries prevent another user from forging device authorization or
  contributions under a different user's key. Transport tampering can still
  disrupt availability; signatures do not prevent deletion or delayed delivery.
- The holder of a user key can impersonate any device of that user and sign
  device-registry updates. Strict registration does not prevent this.
- Compromise affects the user's authority throughout that vault. Removing a
  device ID is insufficient; recovery requires a verified user-key replacement.
- Every device holding the owner's key has owner authority. Restricted
  owner-device permissions and independent device revocation are not provided.
- Key rotation preserves accepted history only through explicit closed-stream
  boundaries; old keys cannot continue those streams. The concrete boundary
  representation and the full canonicalization profile remain open in the draft
  contract and must be specified before interoperable implementations can claim
  complete conformance.
- Sync uses a new format; readers are not required to accept earlier sync or
  security formats.
- An authorized user can fabricate witnesses and trigger remote-stream exclusion.
  The witness policy detects inconsistency but does not prevent denial of service
  by authorized participants.

## Alternatives considered

- **Separate device keys and certificates** — stronger independent device
  control, but additional key management and verification. Rejected for the
  chosen user-level trust boundary.
- **No device registry** — simpler, but provides no explicit signed device set
  and allows unregistered streams. Rejected.
- **Automatically accept unknown device IDs** — undermines a strict registry.
  Rejected; registration precedes acceptance of new contributions.
- **One user key across vaults** — couples otherwise independent vault authority.
  Rejected in favor of vault-specific keys.
- **Separate vault root key** — useful for separating administration from daily
  signing, but adds a key-management layer not required by the chosen model.
- **Legacy compatibility or migration** — rejected because sync is not released
  and a clean new format is simpler and safer than two trust models.
