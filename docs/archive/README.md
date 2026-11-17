# Archive

Superseded, rejected, and historical documents. The directory mirrors the
structure of `docs/` and grows only when a document is actually archived; it has
no empty placeholder subdirectories.

Archived documents are not current requirements or implementation targets.
Archiving preserves their original status and content; it does not approve,
reject, or retroactively change a decision, and it does not change the behavior
of existing code.

## Rules

- Move a document here instead of copying it; no document has two live copies.
- Keep the file name unchanged.
- Add a short archived notice at the top with the reason and, where applicable,
  the current replacement.
- Update incoming links so that historical references keep pointing at the
  historical document, not at its replacement.
- Replaced architectural decisions are archived under `decisions/`; the live
  [decisions catalog](../decisions/README.md) contains only current choices.

## Contents

| Document | Original status | Reason |
|---|---|---|
| [Page file format v1](contracts/page-file-format.md) | Legacy, format version 1 | Replaced by [page file format v3](../contracts/page-file-format-v3.md) |
| [Page file format v2](contracts/page-file-format-v2.md) | Rejected | Rejected revision; the accepted contract is [page file format v3](../contracts/page-file-format-v3.md) |
| [Sync security](contracts/sync-security.md) | Draft | Previous sync model, replaced by the draft [sync security v2](../contracts/sync-security-v2.md) |
| [Deferred device identity](decisions/0003-no-device-identity-until-sync.md) | Accepted | Deferral no longer applies; current identity is defined by [ADR-0010](../decisions/0010-vault-scoped-user-keys-and-device-registry.md) |
| [User/device key hierarchy](decisions/0007-user-device-identity-and-registry.md) | Accepted | Separate device keys and certificates are not part of the current [user-key model](../decisions/0010-vault-scoped-user-keys-and-device-registry.md) |
| [Sync security temporary notes](sync-security-notes.tmp.md) | Temporary, non-normative | Unreviewed rollout and implementation notes for the previous sync model |
