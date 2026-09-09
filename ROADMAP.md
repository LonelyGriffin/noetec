# Roadmap

A date-free picture of what's done, what's being built now, and what's planned.
The milestones map to the [product vision](docs/product/vision.md): its pillars
are the long-term target, and the milestones below are the path there. Detailed
task breakdown lives in the issue tracker, not here.

Legend: ✅ done · 🔨 not done (in progress or planned)

## Now

### M0 — Foundation

The local-first foundation: vaults on plain Markdown files, the block editor,
and the change-history model everything else builds on. Mostly complete.

- ✅ Vault management on plain local `.md` files
  ([ADR-0004](docs/decisions/0004-local-first-markdown-file-storage.md),
  [vault workflow](docs/specs/01-vault-user-workflow.spec))
- ✅ Block-based page model with stable block IDs
  ([ADR-0002](docs/decisions/0002-block-ids-via-fenced-directives.md),
  [file format](docs/specs/file-format.md))
- ✅ Markdown round-trip (parse → edit → serialize) without losing block identity
- ✅ Page/block editor with selection, clipboard, and IME/keyboard/pointer input
- ✅ Operation log (OpLog) — per-device append-only logs with state
  reconstruction ([ADR-0006](docs/decisions/0006-sync-crypto-signatures.md))
- ✅ WAL-backed persistence with crash recovery
- ✅ Unidirectional data flow (Flux) and get_it/watch_it/listen_it DI
  ([ADR-0001](docs/decisions/0001-flux-unidirectional-data-flow.md),
  [ADR-0005](docs/decisions/0005-get-it-di-ecosystem.md))
- 🔨 Foundation hardening and polish

## Next

### M1 — Identity & file-based sync

The first of the three
[sync strategies](docs/product/vision.md#flexible-synchronization): sync the
files with any external tool (Dropbox, Git, WebDAV, …). Underway — identity and
the sync engine are implemented, the milestone is not yet complete end to end.

- ✅ Device and user identity (seed → Ed25519, secure key storage)
  ([ADR-0007](docs/decisions/0007-user-device-identity-and-registry.md))
- ✅ File-based sync engine — OpLog merge, conflict resolution, external-edit
  handling ([ADR-0006](docs/decisions/0006-sync-crypto-signatures.md),
  [sync security](docs/specs/sync-security.md))
- 🔨 End-to-end sync hardening and verification

### M2 — Block ecosystem

The blocks and views that make Noetec more than a Markdown editor.

- 🔨 Block references and backlinks
  ([ADR-0002](docs/decisions/0002-block-ids-via-fenced-directives.md))
- 🔨 Meta-properties — status, start/end dates, custom properties
- 🔨 Templates — note and block
- 🔨 Task and query blocks
- 🔨 Views — outliner, table, kanban, timeline

## Later

### M3 — Server sync & teams/roles

Server-based sync (self-hosted or hosted) and multi-user access.

- 🔨 Server-based sync
- 🔨 Teams, roles, and access control

### M4 — Collaboration

- 🔨 Real-time co-editing via CRDT
- 🔨 P2P sync

### M5 — Mobile & polish

- 🔨 Mobile (phones and tablets)
- 🔨 Built-in calendar
- 🔨 Board mode (spatial canvas view of the same content)
