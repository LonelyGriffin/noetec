# Roadmap

A date-free, one-list view of what's done and what's planned. Each milestone is
decomposed into sub-items, and each sub-item carries its own status.

## Status

- ✅ Done
- 🔨 Now — in progress
- 🔜 Next — up next
- ⏳ Later — planned for the future

## Foundation

- ✅ Vault management — create/open vaults on plain local Markdown files
- ✅ Block-based page model with stable block IDs
- 🔨 Markdown support — basic text blocks only; full block coverage (headings,
  lists, tasks, code, …) is not implemented yet
- ✅ Basic page/block editor — functional, but the UI is still a prototype
- ✅ Operation log (OpLog) with WAL persistence and crash recovery

## UI/UX & quality of life

- 🔜 Rework the prototype editor UI into a polished, friendly interface
- 🔜 Quality-of-life improvements — smoother editing, shortcuts, visual feedback
- 🔜 Onboarding and empty states for new users

## Identity & file-based sync

- ✅ Device and user identity (seed → Ed25519, secure key storage)
- ✅ File-based sync engine — OpLog merge, conflict resolution, external-edit handling
- 🔜 End-to-end sync hardening and verification

## Block ecosystem

- 🔜 Block references and backlinks
- 🔜 Meta-properties — status, start/end dates, custom properties
- 🔜 Templates — note and block
- 🔜 Task and query blocks
- 🔜 Views — outliner, table, kanban, timeline

## Server sync & teams/roles

- ⏳ Server-based sync (self-hosted or hosted)
- ⏳ Teams, roles, and access control

## Collaboration

- ⏳ Real-time co-editing via CRDT
- ⏳ P2P sync

## Mobile & polish

- ⏳ Mobile (phones and tablets)
- ⏳ Built-in calendar
- ⏳ Board mode (spatial canvas view of the same content)
