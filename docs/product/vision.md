# Product Vision

A personal notes, task management, and team collaboration application — open-source at its core.

## Why

Build the dream note-taking tool: one that combines the openness and durability of plain files with the polish and friendliness of modern block editors. Make it free and open-source, with an optional paid hosted service for those who want a turnkey experience.

## Pillars

### File-based storage

All notes, tasks, and calendars live in readable plain-text files (Markdown and similar), like Obsidian — but with a friendlier interface that hides formatting markers and technical symbols, feeling closer to Notion. Your data is never locked in.

### Local-first

Fully functional offline. The network is an enhancement, never a requirement.

### Flexible synchronization

Three sync strategies, giving users freedom over how and where their data lives:

- **File-based sync** — sync the files with any external tool (Git, Dropbox, etc.). Simple, cheap, no server required; supports a reduced feature set (no roles or access control).
- **Server-based sync** — a server holds the master copy and brokers synchronization; supports the full feature set. Available self-hosted or as a hosted service.
- **P2P sync** — devices synchronize directly; a server may orchestrate connections but stores no data. Available self-hosted or as a hosted service.

### Change history with smart conflict resolution

Every file carries a change history with diffs and authorship. Users work with a familiar saved/unsaved model; synchronization exchanges saved states. On conflict, the user resolves it in place in a visual editor. History is tracked per file — there are no branches to manage.

### Block-based structure

Every note is a tree of typed blocks:

- **Block references** — links can point at a specific block, not just a note.
- **Globally unique blocks** — moving a block between notes updates its references automatically.
- **Meta-properties** — every block carries technical properties (ID, modification date) and optional semantic ones (status, start/end dates, deadline), plus user-defined custom properties.
- **Templates** — reusable note and block templates.
- **Task block** — a native block for task management.
- **Query block** — filtered, live views of blocks (e.g. all blocks with status `doing` as a list).

Views: outliner list, table, kanban board, timeline, calendar. Filters: by meta-properties, tags, or text patterns.

### Backlinks

Notes show the blocks that reference them.

### Smart search

Fast, flexible search across everything.

### Document and board modes

A note can be viewed as a linear document or as a freeform spatial board — the same content, two ways of working.

### Built-in calendar

A native calendar that renders blocks by their date meta-properties and lets users create notes directly from it.

### Roles, teams, and access control

Authors can organize into teams, assign roles, and control access to notes (requires server-based sync).

### Mobile

Phones and tablets are first-class citizens with an adapted interface.

### Collaborative editing

Real-time co-editing sessions on top of the change-history model: participants see each other's cursors, edits merge live via CRDT, and the session's output lands as an unsaved change that can then be saved into history.
