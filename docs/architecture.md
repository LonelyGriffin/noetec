# Noetec Architecture

A high-level map of the codebase. It tells you *where* a concern lives so you can
jump straight to the right files; it is not a deep dive. The why behind each
decision lives in the ADRs under `docs/decisions/`, and normative behavior lives
in the specs under `docs/specs/` — those are the contract, this map only points
at it.

Noetec is a **local-first, block-based note editor** built in Flutter/Dart. Notes
are plain Markdown files with YAML frontmatter in a vault on disk; the editor
operates on a typed in-memory block tree and serializes back to Markdown.

## How to read this map

- Data flows in **one direction** (Flux-inspired, ADR-0001): View → command →
  handler → notifier → View.
- Dependencies are wired in **one place**: `lib/app/configure_di.dart` (get_it,
  ADR-0005). If a class needs another, it takes it as a constructor argument —
  never a global lookup.
- The top-level unit of organization is a **system** under `lib/systems/`. Each
  system owns a slice of domain behavior and its own reactive state.

## Directory layout

```
lib/
├── main.dart                 Entry point: configureDI() → VaultSystem.init() → runApp
├── app/                      App composition: DI, root widget, shell, router
│   ├── configure_di.dart     All get_it registrations (the single wiring point)
│   ├── main_app_widget.dart  Root widget (MaterialApp.router + lifecycle saves)
│   ├── app_shell.dart        Desktop/mobile layout shell
│   └── router.dart           go_router: /welcome ↔ /editor (redirects on vault state)
├── entity/                   Pure domain data (no Flutter UI, no services)
│   ├── vault.dart            VaultEntity
│   ├── hlc.dart              Hlc — hybrid logical clock for causal ordering
│   ├── page/                 Page, blocks, text segments, selection, edit actions
│   ├── device/               DeviceIdentity
│   └── user/                 UserIdentity
├── service/                  Infrastructure + domain-adjacent services (interfaces)
├── systems/                  Feature systems (the meat — see Systems below)
├── view/                     Widgets. Thin; watch notifiers, never mutate state
└── (generated *.g.dart)      build_runner output — never hand-edited
```

## The Flux loop (ADR-0001)

State moves in one direction only; no circular dependencies between systems.

```
┌──────────┐  1. user action   ┌─────────┐  2. command.run(param)   ┌──────────┐
│   View   │ ────────────────► │ Command │ ───────────────────────► │  Handler │
│ (widget) │                   │(command_it)│                      │(system)  │
└────▲─────┘                   └─────────┘                        └────┬─────┘
     │                                                                 │ 3. mutates
     │ 5. rebuild                                             entities / state
     │                                                               ▼
┌────┴──────────┐  4. observes   ┌──────────────────────────────────────────┐
│ WatchingWidget│ ◄──────────────│  Notifiers (CustomValueNotifier,         │
│   (watch_it)  │                │  ListNotifier, ValueNotifier) on system  │
└───────────────┘                └──────────────────────────────────────────┘
```

1. **View** — a `WatchingWidget` (e.g. `lib/view/widgets/editor_area.dart`,
   `lib/view/screens/welcome_screen/welcome_screen.dart`). Widgets stay thin:
   they render and react, they hold no business logic.
2. **Command** — a `Command` object owned by a system (from `command_it`),
   e.g. `VaultSystem.createVaultCommand` / `openVaultCommand` /
   `closeVaultCommand` in `lib/systems/vault/vault_system.dart`. A widget calls
   `command.run(param)`; commands expose `.isRunning`, `.errors`, `.value`.
3. **Handler** — the private method backing the command (e.g. `_createVault`,
   `_openVault`). It performs the domain work and mutates the system's state.
4. **Notifiers** — reactive state owned directly by the system (from
   `listen_it`, re-exported by `command_it`): `CustomValueNotifier`,
   `ListNotifier`, plain `ValueNotifier`. There is no ViewModel layer; systems
   hold state and widgets watch it directly (ADR-0005).
5. **WatchingWidget** — subscribes via `watchValue<System, T>((s) => s.field)`
   and rebuilds when the observed notifier changes. The cycle repeats.

**The editor is a variant of the same loop.** Raw keystrokes arrive through
`UserInputService` handlers → `PageEditingSubsystem` mutates the `PageEntity`
block tree → the subsystem emits a `PageEditAction` on `PageActionDispatcher` →
`PersistenceSystem` listens and marks the page dirty. The action-dispatch step is
the editor's equivalent of "command" — it keeps the editor's many micro-edits
(insert, delete, split, merge) decoupled from the persistence concern.

## DI container (ADR-0005)

`lib/app/configure_di.dart` is the **single** place dependencies are wired.
`configureDI()` registers singletons on `GetIt.instance` in dependency order
(services first, then systems that depend on them). Test code injects fakes via
the optional `fileSystem`, `settings`, and `secureKeyStore` parameters, so the
rest of the graph stays real.

Conventions:
- Services are defined as `abstract interface class IXxxService` with an
  `XxxServiceImpl` in the same file (`lib/service/`).
- Systems are concrete classes (not behind interfaces) and take their
  dependencies as constructor parameters.

The stack is `get_it` (DI) + `watch_it` (reactive views) + `listen_it`
(reactive state) + `command_it` (commands) — one coherent ecosystem, per
ADR-0005.

## Systems

### Vault — `lib/systems/vault/`

The root of the domain. `VaultSystem` owns the current vault
(`currentVault: CustomValueNotifier<VaultEntity?>`), the recent-vaults list
(`recentVaults: ListNotifier<VaultEntity>`), and the three vault commands
(create/open/close). It reads/writes the vault manifest (`.noetec/vault.json`),
creates the vault directory skeleton, and emits `ClosingEvent` / `vaultCreated`
streams that other systems subscribe to. `VaultRepositoryImpl` (`IVaultRepository`)
persists the recent-vaults list via `ISettingsService`.

Related (in `lib/service/`): `VaultFileService` (list/create/rename/delete page
files), `RenameController` (multi-phase rename), `PageFileNameSanitizer`.

### Page — `lib/systems/page_system/`

The in-memory document model. `PageSystem` holds the open pages
(`openPages: Map<String, PageEntity>`), the active page (`activePageId`), and an
`openPagesVersion` counter the editor watches for rebuilds. It loads pages from
Markdown (via `MarkdownSystem` + `PageFrontmatterCodec`) and saves them back,
and it persists the session (`.noetec/session.json`).

Three subsystems hang off it, created in its constructor:
- `editing` (`PageEditingSubsystem`) — applies text edits to the block tree and
  emits `PageEditAction`s.
- `selection` (`PageSelectionSubsystem`) — cursor/range selection state.
- `clipboard` (`PageClipboardSubsystem`) — copy/cut/paste in block form.

`PageActionDispatcher` fans each `PageEditAction` out to listeners (notably
`PersistenceSystem`). See also the entities `PageEntity`, `BlockEntity`,
`TextBlockEntity`, `SelectionEntity`, `PageEditAction` under `lib/entity/page/`.

### OpLog — `lib/systems/oplog_system/`

Append-only operation log that records every edit and save per page, giving sync
a replayable, verifiable history. `OpLogSystem` coordinates the pipeline:
- `oplog_models.dart` — `BlockOp`/`FileOp` operations and `OpLogEntry`.
- `oplog_dag.dart` — `OpLogDag` tracks the causal graph topology.
- `block_diff_engine.dart` / `state_reconstruction_engine.dart` — diff and
  rebuild block state from entries.
- `oplog_writer.dart` / `oplog_reader.dart` / `oplog_serializer.dart` — persistence.
- `oplog_signer.dart` / `oplog_verifier.dart` — Ed25519 signing/verification of
  entries (ADR-0006), using `ICryptoService` + `ISecureKeyStore`.

Timestamps use `HlcService` (hybrid logical clocks) for causally-consistent
ordering without wall-clock trust. See `docs/specs/sync-security.md`.

### Persistence — `lib/systems/persistence_system/`

Turns edits into durable files. `PersistenceSystem` listens to
`PageActionDispatcher`, buffers edits in the write-ahead log (`WalService`), and
tracks per-page save state (`clean`/`dirty`/`saving`/`error` notifiers consumed
by the editor tab bar). The save flow: append to WAL → flush → `PageSystem.savePage`
(write Markdown) → `OpLogSystem.recordSave` → clear WAL. `CrashRecoveryService`
+ `WalActionSerializer` replay uncommitted actions after a crash so no edit is
lost.

### Sync — `lib/systems/sync_system/`

Reconciles the local OpLog with changes from other devices/files (`.sync/`).
`SyncSystem` watches the vault, then runs a merge:
- `SyncWatcher` — observes incoming sync changes.
- `VaultWatcher` — observes external edits to vault files.
- `MergeEngine` / `MergeApplier` — compute and apply merges.
- `ConflictResolver` / `ConflictStore` — detect, persist, and resolve conflicts.
- `ExternalEditHandler` — folds externally-made edits back into the OpLog.

State surfaces as `SyncStatus` and per-document `DocumentSyncState`. Deep rules
live in `docs/specs/sync-security.md` and ADR-0006/0007.

### Markdown — `lib/systems/markdown_system/`

The boundary between the block tree and the Markdown file format.
`MarkdownSystem` exposes `parseMarkdown` (text → `TextBlockEntity` list) and
`serializeBlocks` (blocks → text), built on the `markdown` package. A custom
`FencedDirectiveSyntax` (`markdown_parser.dart`) handles `::: {#id}` fenced
directives that carry block IDs (ADR-0002). The canonical file format is
`docs/specs/file-format.md`.

### User Input — `lib/systems/user_input_system/`

Translates platform input events into document edits and selection changes.
`UserInputService` routes to four handlers (in `handlers/`):
- `ImeInputHandler` — text deltas from the IME (the `UserRawTextInputWidget`
  with its `DeltaTextInputClient` is the raw text surface).
- `KeyboardInputHandler` — key events, modifier state, shortcuts.
- `PointerInputHandler` — clicks, drags, selection anchoring.
- `ClipboardInputHandler` — copy/cut/paste/select-all.

All four ultimately drive `PageEditingSubsystem` (and the selection/clipboard
subsystems) on `PageSystem`.

## Entities — `lib/entity/`

Pure data, no Flutter UI and no service dependencies:

| Entity | File | Purpose |
|---|---|---|
| `VaultEntity` | `vault.dart` | vault id, name, root path, created-at |
| `Hlc` | `hlc.dart` | hybrid logical clock (`physicalMs`, `counter`, `deviceId`) |
| `PageEntity` | `page/page.dart` | page id, path, block tree, selection |
| `BlockEntity` / `TextBlockEntity` | `page/block/` | typed block tree (`id`, `parentId`, `children`, `segments`) |
| `TextSegment` (+ `FormattedSegment`, `LinkSegment`) | `page/block/text/` | styled text runs within a block |
| `SelectionEntity` (+ `NoSelection`, `SingleCursor`, `Range`) | `page/selection.dart` | cursor / range state |
| `PageEditAction` (sealed) | `page/page_edit_action.dart` | the edit operations the editor emits |
| `DeviceIdentity` | `device/` | device key + id (ADR-0007) |
| `UserIdentity` | `user/` | user identity (ADR-0007) |

## Services — `lib/service/`

Interface + implementation pairs that systems depend on through DI:

| Interface | Impl | Purpose |
|---|---|---|
| `IFileSystemService` | `FileSystemServiceImpl` | all file I/O (platform-abstraction) |
| `ISettingsService` | `SettingsServiceImpl` | key/value app settings |
| `ISecureKeyStore` | `SecureKeyStoreImpl` | secure storage of keys |
| `ICryptoService` | `CryptoServiceImpl` | signing/hashing primitives |
| `IIdService` | `IdService` | ID generation |
| `IDeviceService` | `DeviceServiceImpl` | device identity & attribution |
| `IUserService` | `UserServiceImpl` | user identity |
| `ITrustStore` | `TrustStoreImpl` | trust decisions (TOFU, pinned) |

Also: `HlcService` (HLC generation), `VaultFileService`, `RenameController`,
`PageFileNameSanitizer`.

## View — `lib/view/`

Thin widgets. They read systems via `di<X>()` and subscribe with `watchValue`;
they call commands/handlers but never mutate entities directly.

- `lib/app/` — `main_app_widget.dart` (root), `app_shell.dart` (desktop sidebar
  shell vs mobile bottom-nav), `router.dart` (go_router, redirects between
  `/welcome` and `/editor` based on `currentVault`).
- `screens/` — `welcome`, `editor`, `settings`, `main_app_loading`.
- `widgets/` — `icon_rail`, `content_panel` (+ `pages`/`settings`/`bookmarks`/
  `journal`), `editor_area`, and `editor/` (`PageEditorWidget`,
  `BlockEditorWidget`, `TextBlockRenderWidget`).

## Pointers to decisions & specs

ADRs (`docs/decisions/`, immutable — supersede, never edit):

- **0001** Flux-inspired unidirectional data flow — the loop above.
- **0002** Block IDs via fenced directives (`::: {#id}`) in Markdown.
- **0003** No device identity until sync is implemented.
- **0004** Local-first, file-based storage as Markdown + YAML frontmatter.
- **0005** get_it DI with the watch_it / listen_it / command_it ecosystem.
- **0006** Ed25519 signatures for sync OpLog security.
- **0007** Multi-user identity and sync registry model.

Specs (`docs/specs/`, normative — RFC 2119):

- `file-format.md` — the page file format (frontmatter, block IDs, hashing).
- `sync-security.md` — sync security format and verification rules.
- `01-vault-user-workflow.spec` — end-to-end vault user workflow.

Product direction: `docs/product/vision.md`; roadmap: `ROADMAP.md`.
