# Noetec Architecture

## Overview

Noetec is a cross-platform Flutter application for block-based note-taking, task management, and team collaboration. It combines the file-based approach of Obsidian (all data stored as readable `.md` files) with the user-friendly interface of Notion (hiding markdown syntax behind a rich visual editor). The application is local-first, supporting seamless offline operation, with flexible multi-device synchronization through file-based sync (Dropbox, Git), server-based sync, or P2P sync.

**Key design principles:**
- **Local-first**: Fully functional without network connection
- **File-based**: All data stored as human-readable markdown files
- **Block-level granularity**: Documents are trees of blocks, each with unique identifiers
- **Unidirectional data flow**: Flux-inspired architecture with clear separation between state and views
- **Offline-capable**: All operations work locally, sync is asynchronous

---

## Technology Stack

**Platform**: Flutter — cross-platform (desktop + mobile)

**Core libraries:**
| Library | Purpose |
|---------|---------|
| `get_it` | Dependency injection container |
| `watch_it` | Reactive widgets (WatchingWidget subscribes to notifiers) |
| `listen_it` | Reactive collections (ValueNotifier, ListNotifier, MapNotifier) |
| `command_it` | Reactive command wrappers (async/sync functions with `.isRunning`, `.errors`, `.value`) |
| `markdown` | Markdown rendering |
| `uuid` | Unique identifier generation |
| `crypto` | SHA-256 hashing for content integrity |
| `yaml` | YAML frontmatter parsing |
| `path_provider` | Platform-specific directory paths |

---

## Layered Structure

The codebase is organized into few layers with strict dependency direction:

```
View Layer (lib/view/)
    ↓ depends on
Systems Layer (lib/systems/)
    ↓ depends on
Services / Infrastructure Layer (lib/service/)
    ↑ uses
Entities (lib/entity/)
```

**View Layer** (`lib/view/`): Reactive widgets that watch system state and dispatch commands. No business logic, no direct entity mutation. Widgets use `WatchingWidget` to subscribe to notifiers and rebuild automatically when state changes.

**Systems Layer** (`lib/systems/`): Feature-based modules containing reactive state and command handlers. Each system owns a specific domain (vault, editor, persistence, etc.) and exposes its state via notifiers. Systems operate on entities and coordinate infrastructure.

**Services / Infrastructure Layer** (`lib/service/`): Infrastructure services with abstract interfaces and implementations in the same file. Provides platform-specific capabilities (filesystem, settings, storage) to systems. Pattern: `abstract interface class IXxxService` + `XxxServiceImpl` in `lib/service/xxx_service.dart`.

**Entities** (`lib/entity/`): Domain models — immutable data structures with no framework dependencies.

**App** (`lib/app/`): App level layer. Bootstraping, navigation, all app orchestration.

---

## Data Flow (Flux-inspired)

The application follows a unidirectional data flow pattern:

```
1. User action in View
   ↓
2. View calls command.run(param) on a System's Command
   ↓
3. Command executes the handler function, performing domain operations on Entities
   ↓
4. Handler updates System's reactive state (Notifier)
   ↓
5. WatchingWidget detects state change and rebuilds
   ↓
6. Back to step 1
```

**Key properties:**
- **Unidirectional**: No circular dependencies between systems
- **Explicit**: All state changes flow through commands
- **Isolated**: Systems cannot directly mutate other systems' state
- **Cross-system communication**: If System A needs System B to perform an action, A calls B's command directly. A can read B's state (watch) but never mutates it.

---

## State Management

**No ViewModel layer** — widgets watch system state directly.

Each system owns its reactive state through notifiers from `listen_it`:
- `ValueNotifier<T>` for single values
- `ListNotifier<T>` for lists
- `MapNotifier<K, V>` for key-value collections

Widgets use `WatchingWidget` from `watch_it` to subscribe to specific notifiers. When a notifier's value changes, the widget automatically rebuilds.

**Commands** are created via `command_it` factory methods (`Command.createAsync*`, `Command.createSync*`). Each system exposes commands as fields. Views call `command.run(param)` to trigger state changes.

**Entities are immutable**: All mutations create new objects. Systems hold the "current state" in notifiers, but the underlying entities never mutate — they are replaced with new versions.

---

## Systems Overview

The application is divided into feature-based systems, each responsible for a specific domain:

| System | Responsibility |
|--------|----------------|
| **NavigationSystem** | App screen state, routing between screens (vault picker, editor, settings) |
| **MarkdownSystem** | Conversion between markdown text and block structures (parse and serialize) |
| **EditorSystem** | Document editing, user actions (insert, delete, move), cursor and selection state |
| **VaultSystem** | Vault lifecycle (create, open, close), recent vaults list. Current iteration: minimal MVP without HLC, oplog, WAL |
| **PersistenceSystem** | Autosave, dirty tracking, WAL (Write-Ahead Log) for crash recovery, session restoration |
| **OplogSystem** | Block-level operation log, diff engine, DAG (Directed Acyclic Graph), state reconstruction from oplog |
| **SyncSystem** | File watchers, merge engine, conflict resolution, external edit handling |

**System dependencies** (directional, no cycles):

```
EditorSystem → PersistenceSystem (trigger save on changes)
PersistenceSystem → VaultSystem (write files to disk)
PersistenceSystem → OplogSystem (record operations on save)
OplogSystem → (internal: builds DAG from oplog entries)
SyncSystem → OplogSystem (read and merge oplogs from other devices)
SyncSystem → VaultSystem (detect external file edits)
SyncSystem → PersistenceSystem (notify of remote changes, trigger reload)
```

Each system is a folder under `lib/systems/` containing:
- State notifiers (reactive state)
- Command handlers (process commands, operate on entities)
- Models (system-specific data structures)

---

## Vault on Disk

The vault is a directory on the user's filesystem with the following structure:

```
<vault-root>/
├── .noetec/                          # Device-local (NOT synced)
│   ├── device.json                   # Device identity (UUID, name, last HLC)
│   ├── config.json                   # Vault configuration
│   ├── session.json                  # Last session state (open documents, sidebar)
│   ├── wal/                          # Write-Ahead Log files (crash recovery)
│   └── cache/                        # Cached data (file tree, etc.)
│
├── .sync/                            # Synced between devices
│   └── pages/                        # Per-file oplog logs
│       └── <relative-path>/
│           ├── <device-uuid-1>.oplog.jsonl
│           └── <device-uuid-2>.oplog.jsonl
│
└── pages/                            # User's markdown files (snapshots)
    ├── welcome.md
    └── notes/
        └── project.md
```

**Key concepts:**
- `pages/` contains the current snapshot of all files (what the user sees)
- `.sync/pages/` contains the operation log for each file (one `.oplog.jsonl` per device per file)
- `.noetec/` is device-local and not synced (contains device identity, session state, WAL)

**Markdown file format:**

Each `.md` file in `pages/` starts with YAML frontmatter:

```markdown
---
id: <uuid>
content_hash: sha256:<hex>
modified: <iso8601>
modified_by: <device-uuid>
---

::: header abc123
# Document Title
:::

::: paragraph def456
Paragraph text with **bold** and *italic*.
:::

::: task fet456 status="TODO"
- [ ] Some root task
   ::: task fer764 status="DONE"
   - [ ] Some sub task task
   :::
:::
```

- `id`: UUID of the document (stable across renames/moves)
- `content_hash`: SHA-256 of the content after frontmatter (for detecting external edits)
- `modified`: Timestamp of last save
- `modified_by`: UUID of the device that made the last save
- Blocks are wrapped in customblocks directives `::: <type> <id> ...other attrs` to ensure each block has a unique identifier

---

## Key Algorithms

### HLC (Hybrid Logical Clock)

HLC provides causal ordering of events across multiple devices without coordination. It combines physical wall clock time with a logical counter to ensure:
- **Causality**: If event A happened before event B on the same device, HLC(A) < HLC(B)
- **Uniqueness**: Counter + device ID ensure uniqueness even with identical wall clock times
- **Approximation**: Tied to physical time for human readability

Each device maintains its last HLC. When generating a new HLC, the device takes the maximum of its wall clock and last HLC's physical time, increments the counter if needed, and appends its device ID. When receiving a remote HLC, the device merges it with its local state similarly.

### Block Diff

When saving a document, the system computes the difference between the previous and current block states. The diff algorithm:
1. Classifies blocks as deleted, inserted, or common (present in both)
2. Among common blocks, identifies which were updated (content changed)
3. Detects moved blocks using Longest Increasing Subsequence (LIS) on block order
4. Generates operations: BlockDelete, BlockInsert, BlockUpdate, BlockMove

The diff is compact (only changed blocks) and preserves block IDs across moves.

### Oplog DAG

Operations from all devices form a Directed Acyclic Graph (DAG). Each operation has:
- `hlc`: Hybrid Logical Clock timestamp
- `parent`: HLC of the previous operation (forms a chain per device)
- `otherParents`: array of other parents for merge operations (connects diverged branches)

The DAG topology can be:
- **Single**: Only one head (one device, linear history)
- **Linear**: Multiple devices but all heads on one line (fast-forward possible)
- **Diverged**: Heads have diverged (3-way merge needed)

To find the Lowest Common Ancestor (LCA) of two or more diverged heads, the algorithm performs a bidirectional BFS upward through parent links until a common ancestor is found.

### State Reconstruction

To reconstruct the document state at any point in the DAG:
1. Collect all ancestor operations from the root (file_create) to the target operation
2. Sort them topologically (by HLC)
3. Replay operations sequentially: start with empty document, apply each operation

Operations are idempotent (e.g., deleting a non-existent block is a no-op), allowing safe replay even with partial or corrupted oplogs.

---

## Implementation Phases

The project is implemented in six phases, each building on the previous:

**Phase 1: Vault Foundation (Minimal MVP)**
Implement vault management — create, open, close vaults, recent vaults list with persistence. Vault is a directory with `.noetec/vault.json` metadata. No HLC, oplog, or WAL in this iteration.

**Phase 2: UI Shell & Navigation**
Build the app layout (sidebar + editor), file tree widget with expand/collapse, desktop and mobile layouts (responsive), navigation between screens (vault picker, editor), and dialogs for creating/renaming/deleting files and folders.

**Phase 3: Editor & Persistence**
Implement the document editor with user actions (insert, delete, move, format), custom rendering for blocks with cursor and selection, debounced autosave (3 seconds) plus manual Ctrl+S, WAL for crash recovery, session restoration (reopen last documents and sidebar state), and dirty state tracking with save indicators.

**Phase 4: Oplog Engine**
Record block-level operations to oplog on each save, implement the diff engine to compute changes between document states, build the DAG from oplog entries across devices, implement state reconstruction from oplog, and add integrity checking (verify hash matches after replay).

**Phase 5: Sync & Merge**
Implement file watchers to detect changes in `.sync/` (from other devices) and `pages/` (from external editors), build the 3-way merge engine with conflict detection, implement conflict resolution UI, handle file-level operations (rename, delete) across devices, and notify users of remote changes and conflicts.

**Phase 6: External Vault**
Abstract the filesystem with a platform-independent interface, implement file picker for choosing vault location, support multiple vaults with hot-swap (close current, open another), implement platform-specific access (SAF for Android, security-scoped bookmarks for macOS), and add vault validation and error handling.

**Milestones:**
- After Phase 3: Functional offline editor with autosave and crash recovery
- After Phase 5: Full file-based sync (works with Dropbox, Git, etc.)
- After Phase 6: Production-ready on all platforms

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Block-level granularity** (not line-level) for operations and merge | Balances merge precision with implementation complexity. Blocks already have IDs (fenced directives), making block-level tracking natural. Line-level would require parsing markdown structure in oplog. |
| **HLC for ordering** (not wall clock, not vector clock) | Provides causal ordering without coordination between devices. Tied to physical time for human readability. Simpler than vector clocks, more robust than wall clock alone. |
| **JSON Lines for oplog format** (append-only) | Standard format for event logs. Human-readable, line-by-line processing, compatible with text diff tools. Append-only is simple and crash-safe. |
| **Manual Ctrl+S** | For mvp save files only manuals |
| **WAL debouncing for InsertText (250ms)** | Fast typing generates hundreds of events per second. Batching consecutive InsertText events reduces WAL size and I/O overhead. |
| **Delete/modify conflict: keep modified** | Data preservation is more important than honoring deletions. If one device deleted a block and another modified it, the modified version is kept and the user is notified. |
| **Polling-based file watching for MVP** | Simple and works on all platforms. Native file watching (inotify, FSEvents) is faster but platform-specific. Polling is a reliable fallback. Native support planned for Phase 6. |
| **Merge block ordering: "ours" as baseline** | When merging, "ours" order is used as the base. Blocks inserted by "theirs" are placed relative to their nearest anchor in "ours". If both sides moved the same block, "ours" wins. This provides deterministic, predictable merge results. |
| **No ViewModel layer** | With watch_it/listen_it, services can hold reactive state directly. ViewModels would add an unnecessary layer of indirection. Widgets watch system state directly, keeping the architecture simpler. |
| **Unidirectional data flow** | All state changes flow through commands. This makes the data flow explicit, testable, and prevents circular dependencies. Inspired by Flux/Redux patterns from web development. |
| **Feature-based system organization** | Each system is a self-contained folder with its state, handlers, and models. This makes systems easy to understand, test, and refactor independently. |
