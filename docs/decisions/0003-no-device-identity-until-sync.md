# 0003: No Device Identity Until Sync Is Implemented

## Context

The target design attributes every change to the device that made it: a device identity (a per-device UUID, stored with other device-local state) and a `modified_by: <device-uuid>` field in each file's frontmatter. Device attribution is what makes multi-device merge, conflict resolution, and per-device operation logs meaningful.

However, sync — the only feature that consumes device attribution — is not implemented yet. Adding device identity now would mean maintaining identity lifecycle (generation, persistence, naming) and a frontmatter field that nothing reads.

## Decision

Defer device identity. Do not generate or store a device UUID, and do not write `modified_by` into file frontmatter, until sync is implemented. Frontmatter in the current format omits `modified_by`; the field (and the device identity it references) will be introduced together with the sync work that requires it.

## Status

Accepted.

## Consequences

- Positive: less code to build, test, and maintain in the pre-sync phases — no identity lifecycle management with no consumer.
- Positive: frontmatter stays minimal; files written now are not polluted with placeholder fields carrying meaningless values.
- Negative: when sync lands, existing files must be migrated to add `modified_by` (or tolerate its absence), and a device identity must be provisioned for existing vaults.
- Negative: until then there is no attribution of changes at all — acceptable only because a single-device local-first MVP has exactly one possible author.

## Alternatives considered

- **Write `modified_by` from day one with a provisional device ID** — rejected: adds identity lifecycle complexity before any feature consumes it, and the provisional identity semantics would likely need rework when real sync semantics arrive.
- **Keep device identity but omit `modified_by`** — rejected: an identity with no field referencing it is dead weight; the two must land together to be useful.
