# Noetec Architecture

A high-level map of the codebase. It tells you *where* a concern lives so you can
jump straight to the right files; it is not a deep dive. The why behind each
decision lives in the ADRs under `docs/decisions/`. User-facing behavior lives
in `docs/specs/`; formats and protocols live in `docs/contracts/`. Accepted
requirements govern their stated scope; this map only points at them. See
[the documentation index](README.md) for document status and boundaries.

Noetec is a **local-first, block-based note editor** built in Flutter/Dart. Notes
are plain Markdown files with YAML frontmatter in a vault on disk; the editor
operates on a typed in-memory block tree and serializes back to Markdown.

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

Views are thin `WatchingWidget`s (e.g. `lib/view/widgets/editor_area.dart`,
`lib/view/screens/welcome_screen/welcome_screen.dart`): they render and react,
never holding business logic. A user action calls `command.run(param)` on a
`Command` owned by a system (from `command_it`) — for instance
`VaultSystem.createVaultCommand`, `openVaultCommand`, `closeVaultCommand` in
`lib/systems/vault/vault_system.dart`, which expose `.isRunning`, `.errors`, and
`.value`. The private handler behind each command (`_createVault`, `_openVault`)
does the domain work and mutates notifiers the system owns:
`CustomValueNotifier`, `ListNotifier`, plain `ValueNotifier` (from `listen_it`,
re-exported by `command_it`). There is no ViewModel layer; widgets watch those
notifiers directly through `watchValue<System, T>((s) => s.field)` and rebuild
when they change (ADR-0005).

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
  dependencies as constructor parameters — never through a global lookup.

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
ordering without wall-clock trust. See `docs/contracts/sync-security.md`.

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
live in `docs/contracts/sync-security.md` and ADR-0006/0007.

### Markdown — `lib/systems/markdown_system/`

The boundary between the block tree and the Markdown file format.
`MarkdownSystem` exposes `parseMarkdown` (text → `TextBlockEntity` list) and
`serializeBlocks` (blocks → text), built on the `markdown` package. A custom
`FencedDirectiveSyntax` (`markdown_parser.dart`) handles `::: {#id}` fenced
directives that carry block IDs (ADR-0002). The canonical file format is
`docs/contracts/page-file-format.md`.

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

ADRs live in `docs/decisions/` (immutable — supersede, never edit); behavior
scenarios live in `docs/specs/`; technical contracts live in `docs/contracts/`
(RFC 2119, subject to explicit document status); product direction is in
`docs/product/vision.md`, and the roadmap is `docs/product/ROADMAP.md`. The full topic →
document index for agents stays in `CLAUDE.md`.
