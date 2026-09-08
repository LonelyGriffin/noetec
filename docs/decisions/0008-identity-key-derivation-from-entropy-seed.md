# 0008: Identity Key Derivation Is From the Entropy Seed (HKDF), Not the Mnemonic

## Status

Accepted.

Supersedes (partially) ADR-0007 §1: the clause *"The seed is produced from the
BIP39 mnemonic via PBKDF2-HMAC-SHA512 (2048 iterations), per BIP39."* is
withdrawn as it is self-contradictory. ADR-0007 §1's first bullet (the 32-byte
seed is the source of the identity key), its HKDF clause, and the rest of
ADR-0007 stand unchanged.

## Context

ADR-0007 §1 describes the user identity in two places that disagree.

- First bullet: a user is an Ed25519 identity key pair **"derived
  deterministically from a 32-byte seed (backed up as a BIP39 mnemonic)."**
- Later clause: *"The seed is produced from the BIP39 mnemonic via
  PBKDF2-HMAC-SHA512 (2048 iterations), per BIP39."*

These cannot both be true. The first bullet makes the 32-byte seed the input to
key derivation and treats the mnemonic as its backup. The later clause makes the
mnemonic the input and the seed its output — the inverse relationship — and
introduces a PBKDF2 step that appears nowhere else in ADR-0007, in
`docs/specs/sync-security.md` §2.1, or in the approved NOET-26 design.

This is a standard BIP39 slip: in a real BIP39 wallet the mnemonic *is* the
master-secret source and PBKDF2 expands it to the master key. Noetec does not
use BIP39 that way. The 32-byte entropy seed is the master secret; the 24-word
mnemonic is only its human-readable backup. Key derivation is a single
HKDF-SHA256 step over the entropy seed — exactly as ADR-0007 §1's first bullet
and its HKDF clause already state.

The reference implementation (NOET-26, `lib/service/crypto_service.dart`,
`CryptoServiceImpl.deriveIdentityKeyPair`) follows the first bullet and the HKDF
clause: entropy seed → HKDF-SHA256 → Ed25519 seed. It does **not** run PBKDF2
and does **not** derive the key from the mnemonic.

## Decision

The authoritative derivation chain for a Noetec user identity is, exactly:

1. A **32-byte entropy seed** is generated (the master secret).
2. That seed is **backed up** as a 24-word BIP39 mnemonic. Restoring it via
   `mnemonicToEntropy` MUST reproduce the identical 32-byte entropy seed. The
   mnemonic is a backup of the seed, never the source of key derivation.
3. The **identity key** is derived from the entropy seed (not the mnemonic)
   with **HKDF-SHA256** (RFC 5869), `salt = "noetec.identity.v1"`,
   `info = "noetec-identity-key"`, 32-byte output used as the Ed25519 secret
   seed, then `Ed25519.newKeyPairFromSeed`.

**PBKDF2 (and BIP39's mnemonic→key expansion) is NOT part of identity key
derivation.** The mnemonic is used only for human backup and for recovering the
entropy seed on another device.

This aligns the documentation with ADR-0007 §1's first bullet, its HKDF clause,
`docs/specs/sync-security.md` §2.1, and the NOET-26 implementation.

## Status

Accepted.

Supersedes the PBKDF2 clause in ADR-0007 §1 ("The seed is produced from the
BIP39 mnemonic via PBKDF2-HMAC-SHA512 (2048 iterations), per BIP39"), which
contradicted ADR-0007 §1's first bullet and the NOET-26 implementation. ADRs are
immutable, so this ADR — not an edit of ADR-0007 — is the authoritative source.

## Consequences

- Positive: one unambiguous derivation path (entropy seed → HKDF → Ed25519);
  the mnemonic is clearly a backup, not a key-expansion step.
- Positive: implementations that restore an identity from the mnemonic and then
  HKDF the recovered entropy seed are provably correct and deterministic across
  devices.
- Negative: none — this withdraws a contradictory clause rather than changing
  behavior.
