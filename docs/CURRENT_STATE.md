# Current Implementation State

This document describes the **current implementation state** of Noetec as of the Editor MVE completion. For the overall architecture vision and future plans, see [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## What's Implemented

### 1. Vault Management (Complete)

**Location:** `lib/systems/vault/`

**Capabilities:**
- Create new vault (directory structure + metadata)
- Open existing vault
- Close vault
- Recent vaults list with persistence

**Vault Structure:**
```
<vault-root>/
├── .noetec/
│   └── vault.json          # VaultEntity metadata (id, name, rootPath, createdAt)
└── pages/
    ├── welcome.md           # Auto-created on vault init
    └── ...                  # User's .md files
```

**Key Files:**
- `vault_system.dart` — vault lifecycle management
- `vault_repository.dart` — recent vaults persistence (via `shared_preferences`)

**Reactive State:**
- `currentVault: CustomValueNotifier<VaultEntity?>` — currently open vault
- `recentVaults: ListNotifier<VaultEntity>` — list of recently opened vaults

**Commands:**
- `createVaultCommand` — async command to create new vault
- `openVaultCommand` — async command to open existing vault
- `closeVaultCommand` — sync command to close current vault

---

### 2. File System Abstraction (Complete)

**Location:** `lib/service/file_system_service.dart`

**Interface:**
```dart
abstract interface class IFileSystemService {
  Future<bool> directoryExists(String path);
  Future<void> createDirectory(String path);
  Future<String> readFile(String path);
  Future<void> writeFile(String path, String content);
  Future<bool> fileExists(String path);
  Future<String?> pickDirectory();
  Future<List<FileEntry>> listDirectory(String path);  // Added in Editor MVE
  Future<void> deleteFile(String path);                 // Added in Editor MVE
}
```

**Implementation:** `FileSystemServiceImpl` uses `dart:io` for file operations.

**Models:**
```dart
final class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final DateTime? lastModified;
}
```

---

### 3. File Tree Scanning (Complete)

**Location:** `lib/service/vault_file_service.dart`

**Purpose:** Scan `pages/` directory and build reactive file tree for UI.

**Models:**
```dart
sealed class PageFileNode {
  String get name;
}

final class PageFileFolder extends PageFileNode {
  final String name;
  final List<PageFileNode> children;
}

final class PageFileItem extends PageFileNode {
  final String name;
  final String relativePath;   // e.g., "welcome.md" or "notes/project.md"
  final String pageId;         // from frontmatter
  final DateTime? modified;
}
```

**Reactive State:**
- `fileTree: ListNotifier<PageFileNode>` — reactive file tree

**Methods:**
- `scanFileTree(String vaultRootPath)` — scans `pages/` directory recursively
- Reads frontmatter from each `.md` file to extract `pageId`
- Skips hidden files (starting with `.`)
- Sorts: folders first, then files, alphabetically

---

### 4. Markdown System (Complete)

**Location:** `lib/systems/markdown_system/`

**Purpose:** Convert between markdown text and block structures.

**Parser** (`markdown_parser.dart`):
- Uses `markdown` package with GitHub Flavored Markdown extension set
- Supports fenced directives `::: {#id}` for block identification
- Parses inline formatting: **bold**, *italic*, [links](url)
- Returns `List<TextBlockEntity>`

**Serializer** (`markdown_serializer.dart`):
- Converts `List<TextBlockEntity>` back to markdown
- Wraps each block in `::: {#blockId}` directives
- Escapes markdown special characters
- Preserves formatting (bold, italic, links)

**Key Features:**
- Block IDs are preserved across parse/serialize cycles
- Empty content produces at least one empty block
- Supports nested formatting

---

### 5. Frontmatter Codec (Complete)

**Location:** `lib/systems/page_system/page_frontmatter_codec.dart`

**Purpose:** Parse and generate YAML frontmatter in `.md` files.

**Frontmatter Format:**
```yaml
---
id: <uuid>
content_hash: sha256:<hex>
modified: <iso8601>
---
```

**Model:**
```dart
final class PageFrontmatter {
  final String id;
  final String contentHash;
  final DateTime modified;
}
```

**Methods:**
- `parse(String fileContent)` → `({PageFrontmatter frontmatter, String content})`
  - Extracts frontmatter using regex `^---\r?\n(.*?)\r?\n---\r?\n?`
  - Generates fresh ID if frontmatter missing or malformed
  - Returns normalized content (strips leading newline)
  
- `encode(PageFrontmatter frontmatter, String content)` → `String`
  - Serializes frontmatter as YAML block
  - Appends content after frontmatter
  
- `computeContentHash(String content)` → `String`
  - SHA-256 hex digest of UTF-8 encoded content

**Edge Cases Handled:**
- Missing frontmatter → generates fresh ID
- Malformed YAML → generates fresh ID
- Empty file → generates fresh ID
- Windows line endings (`\r\n`) → normalized

---

### 6. Page System (Complete)

**Location:** `lib/systems/page_system/`

**Purpose:** Manage open pages, load/save from disk.

**Core State:**
```dart
class PageSystem {
  final Map<String, PageEntity> openPages = {};
  final ValueNotifier<String?> activePageId = ValueNotifier(null);
  
  String? _vaultRootPath;
  final Map<String, String> _pathToPageId = {};  // path → pageId cache
}
```

**Key Methods:**

**`loadPage(String relativePath)`** — async
1. Check path-to-ID cache (avoid re-reading)
2. Read file via `IFileSystemService.readFile()`
3. Parse frontmatter via `PageFrontmatterCodec.parse()`
4. Parse markdown via `MarkdownSystem.parseMarkdown()`
5. Create `PageEntity` with blocks
6. Register in `openPages` map
7. Set as `activePageId`
8. Return `PageEntity`

**`savePage(String pageId)`** — async
1. Get `PageEntity` from `openPages`
2. Serialize blocks via `MarkdownSystem.serializeBlocks()`
3. Compute content hash
4. Encode with frontmatter via `PageFrontmatterCodec.encode()`
5. Write file via `IFileSystemService.writeFile()`

**`setVaultRoot(String path)`** — called when vault opens
- Stores vault root path for resolving absolute paths

**`clearAllPages()`** — called when vault closes
- Disposes all open pages
- Clears caches

**Subsystems:**

**PageEditingSubsystem** — text editing operations
- `insertText(int flatOffset, String text)`
- `deleteTextBack(int flatOffset)`
- `deleteTextForward(int flatOffset)`
- `splitBlock(int splitOffset)`
- `replaceText(int flatStart, int flatEnd, String replacement)`
- `deleteSelection()`

**PageSelectionSubsystem** — cursor and selection management
- `moveCursor(CursorMoveDirection direction)`
- `extendSelection(CursorMoveDirection direction)`
- `setRangeSelection(...)`
- `selectAll()`
- `handleClick(String blockId, int segmentIndex, int offset)`
- `swapSelectionAnchors()`

**PageClipboardSubsystem** — clipboard operations
- `handleCopy()`
- `handleCut()`
- `handlePaste()`
- `handleSelectAll()`

---

### 7. Entity Model (Complete)

**Location:** `lib/entity/`

**PageEntity:**
```dart
class PageEntity {
  final String id;
  String? relativePath;  // vault-relative path, e.g., "pages/welcome.md"
  final Map<String, BlockEntity> blocks = {};
  final List<BlockEntity> rootBlocks = [];
  final ValueNotifier<SelectionEntity> selection = ValueNotifier(const NoSelectionEntity());
}
```

**BlockEntity** (abstract):
```dart
abstract class BlockEntity {
  final String? parentId;
  final String id;
  final List<BlockEntity> children;
}
```

**TextBlockEntity:**
```dart
class TextBlockEntity extends BlockEntity {
  final ListNotifier<TextSegment> segments;
  
  String computeAllSegmentsText();
  int flatOffsetFromCursor(int segmentIndex, int offset);
  CursorPositionInTextBlock cursorPosFromFlatOffset(int flatOffset);
  ({int segmentIndex, int offset})? charPosFromFlatOffset(int flatOffset);
  (int, int) wordBoundaryAt(int flatOffset);
}
```

**TextSegment** hierarchy:
```dart
class TextSegment {
  final String text;
}

class FormattedSegment extends TextSegment {
  final TextFormat format;  // bold, italic, etc.
}

class LinkSegment extends TextSegment {
  final String url;
}
```

**SelectionEntity** (sealed):
```dart
sealed class SelectionEntity {}

class NoSelectionEntity extends SelectionEntity {}

class SingleCursorSelectionEntity extends SelectionEntity {
  final CursorPositionInDocument cursorPos;
}

class RangeSelectionEntity extends SelectionEntity {
  final CursorPositionInDocument anchor;
  final CursorPositionInDocument extent;
}
```

**CursorPositionInDocument** (sealed):
```dart
sealed class CursorPositionInDocument {
  final String blockId;
}

class CursorPositionInTextBlock extends CursorPositionInDocument {
  final int segmentIndex;
  final int offset;
}
```

---

### 8. User Input System (Complete)

**Location:** `lib/systems/user_input_system/`

**Purpose:** Coordinate all user input (keyboard, IME, pointer, clipboard).

**Architecture:**
```
UserInputService
├── KeyboardInputHandler    — hardware keyboard events
├── ImeInputHandler         — text input method editor (IME)
├── PointerInputHandler     — mouse/touch interactions
└── ClipboardInputHandler   — clipboard operations
```

**UserRawTextInputWidget:**
- Wraps child widget with `Focus` and `DeltaTextInputClient`
- Manages `TextInputConnection` for IME
- Routes key events to `KeyboardInputHandler`
- Routes text deltas to `ImeInputHandler`

**KeyboardInputHandler:**
- Tracks modifier keys (Ctrl, Shift, Alt, Meta)
- Handles shortcuts:
  - `Ctrl+S` — save page
  - `Ctrl+A` — select all
  - `Ctrl+C` — copy
  - `Ctrl+X` — cut
  - `Ctrl+V` — paste
  - `Backspace` — delete backward
  - `Delete` — delete forward
  - `Enter` — split block
  - `Arrow Left/Right` — move cursor (with Shift for selection)
- Routes character input to `PageEditingSubsystem.insertText()`

**ImeInputHandler:**
- Manages IME state per page (`TextEditingValue`)
- Handles text deltas (insertions, deletions, replacements)
- Syncs IME state after non-IME events (clicks, keyboard navigation)

**PointerInputHandler:**
- Handles click, shift+click, drag start/move/end
- Manages drag selection state
- Updates selection via `PageSelectionSubsystem`

---

### 9. Editor Widgets (Complete)

**Location:** `lib/view/widgets/editor/`

**Widget Hierarchy:**
```
PageEditorWidget (root editor widget)
├── UserRawTextInputWidget (IME input)
│   └── Listener (pointer events)
│       └── ListView.builder (blocks)
│           └── BlockEditorWidget (per-block)
│               └── TextBlockRenderWidget (LeafRenderObjectWidget)
│                   └── TextBlockRenderBox (custom RenderBox)
```

**PageEditorWidget:**
- Root widget for editing a page
- Wraps content in `UserRawTextInputWidget` for IME
- `Listener` for passive pointer event handling
- `ListView.builder` for rendering blocks
- Hit-testing: converts global coordinates to block/segment/offset

**BlockEditorWidget:**
- Renders single block with selection awareness
- Listens to `PageEntity.selection` for reactive updates
- Computes `BlockSelectionInfo` via pure function
- Passes selection info to `TextBlockRenderWidget`

**TextBlockRenderWidget / TextBlockRenderBox:**
- `LeafRenderObjectWidget` + custom `RenderBox`
- Text layout via `TextPainter`
- Segment-aware rendering (plain, bold, italic, links)
- Paint order: selection highlight → text → cursor
- Cursor blink (500ms timer)
- Hit-testing: `getPositionForLocalOffset(Offset)` → `(segmentIndex, offset)`

**BlockSelectionInfo** (sealed):
```dart
sealed class BlockSelectionInfo {}

class BlockNotSelected extends BlockSelectionInfo {}
class BlockFullySelected extends BlockSelectionInfo {}
class BlockWithCursor extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;
}
class BlockWithRange extends BlockSelectionInfo {
  final CursorPositionInTextBlock anchorCursorPos;
  final CursorPositionInTextBlock extentCursorPos;
}
class BlockSelectedFromStart extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;
}
class BlockSelectedToEnd extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;
}
```

**computeBlockSelectionInfo()** — pure function
- Takes: `blockId`, `SelectionEntity`, `flatBlockIds()`, `selectedBlockIds`
- Returns: `BlockSelectionInfo` for the block
- No widget/model dependencies → independently testable

---

### 10. UI Shell (Complete)

**Location:** `lib/app/`, `lib/view/`

**App Shell Structure:**
```
AppShell
├── IconRail (left sidebar with panel icons)
├── ContentPanel (collapsible left panel)
│   ├── PagesPanel (file tree)
│   ├── JournalPanel (placeholder)
│   ├── BookmarksPanel (placeholder)
│   └── SettingsPanel (placeholder)
└── EditorArea (main content)
    ├── EditorTabBar (tabs for open pages)
    └── PageEditorWidget (active page editor)
```

**PagesPanel:**
- Watches `VaultFileService.fileTree`
- Renders file tree with folders and files
- Click on file → loads page and opens tab
- Click on folder → expands/collapses

**EditorArea:**
- Watches `LayoutUISystem.openTabs` and `activeTabId`
- Renders `PageEditorWidget` for active tab
- Shows "Open a page" message when no tabs

**LayoutUISystem:**
- Manages UI state (active panel, open tabs, active tab)
- `openTab(EditorTab)` — opens tab or activates if already open
- `closeTab(String tabId)` — closes tab and activates adjacent

---

### 11. Routing (Complete)

**Location:** `lib/app/router.dart`

**Routes:**
```dart
GoRouter(
  initialLocation: '/welcome',
  refreshListenable: vaultListenable,
  redirect: (context, state) {
    final vault = GetIt.I<VaultSystem>().currentVault.value;
    final onWelcome = state.uri.path == '/welcome';
    
    if (vault == null && !onWelcome) return '/welcome';
    if (vault != null && onWelcome) return '/editor';
    return null;
  },
  routes: [
    GoRoute(path: '/welcome', builder: ...),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/editor', builder: ...),
      ],
    ),
  ],
)
```

**Behavior:**
- Starts at `/welcome` (vault picker)
- Redirects to `/editor` when vault opens
- Redirects to `/welcome` when vault closes
- `/editor` wrapped in `AppShell` (provides sidebar + editor layout)

---

### 12. Dependency Injection (Complete)

**Location:** `lib/app/configure_di.dart`

**Registered Services:**
```dart
getIt.registerSingleton<IIdService>(IdService());
getIt.registerSingleton<IFileSystemService>(FileSystemServiceImpl());
getIt.registerSingleton<ISettingsService>(SettingsServiceImpl());
getIt.registerSingleton<IVaultRepository>(VaultRepositoryImpl(...));
getIt.registerSingleton<VaultSystem>(VaultSystem(...));
getIt.registerSingleton<LayoutUISystem>(LayoutUISystem());
getIt.registerSingleton<MarkdownSystem>(MarkdownSystem(...));
getIt.registerSingleton<PageSystem>(PageSystem(...));
getIt.registerSingleton<VaultFileService>(VaultFileService(...));
getIt.registerSingleton<UserInputService>(UserInputService());
```

**Vault Sync Listener:**
```dart
vaultSystem.currentVault.addListener(() {
  final vault = vaultSystem.currentVault.value;
  if (vault != null) {
    pageSystem.setVaultRoot(vault.rootPath);
    vaultFileService.scanFileTree(vault.rootPath);
  } else {
    pageSystem.clearAllPages();
  }
});
```

---

## Data Flow Examples

### Open Vault
```
User selects vault directory
→ VaultSystem.openVaultCommand.run(path)
  → Read .noetec/vault.json
  → Parse VaultEntity
  → Set currentVault.value = vault
  → Add to recentVaults
→ Router redirects to /editor
→ currentVault listener fires:
  → PageSystem.setVaultRoot(vault.rootPath)
  → VaultFileService.scanFileTree(vault.rootPath)
→ PagesPanel rebuilds with file tree
```

### Load Page
```
User clicks file in PagesPanel
→ PageSystem.loadPage(relativePath)
  → Check _pathToPageId cache
  → IFileSystemService.readFile(absolutePath)
  → PageFrontmatterCodec.parse(fileContent)
  → MarkdownSystem.parseMarkdown(content)
  → Create PageEntity with blocks
  → Register in openPages
  → Set activePageId
→ LayoutUISystem.openTab(EditorTab(id, title))
→ EditorArea rebuilds
→ PageEditorWidget(pageId) renders
```

### Edit Text
```
User types character
→ KeyboardInputHandler.handleKeyEvent()
  → Check modifier keys
  → Route to _handleHardwareCharacterInput()
→ PageEditingSubsystem.insertText(flatOffset, char)
  → Get active page and cursor position
  → Find segment at cursor
  → Insert character into segment text
  → Update cursor position
  → Set page.selection.value = new cursor
→ PageEntity.selection notifies listeners
→ BlockEditorWidget rebuilds
→ TextBlockRenderBox repaints with new text
```

### Save Page (Ctrl+S)
```
User presses Ctrl+S
→ KeyboardInputHandler._handleSave(pageId)
→ PageSystem.savePage(pageId)
  → Get PageEntity from openPages
  → MarkdownSystem.serializeBlocks(rootBlocks)
  → PageFrontmatterCodec.computeContentHash(markdown)
  → PageFrontmatterCodec.encode(frontmatter, markdown)
  → IFileSystemService.writeFile(absolutePath, fileContent)
```

### Select Text (Mouse Drag)
```
User clicks and drags in editor
→ PageEditorWidget._onPointerDown(event)
  → Hit-test: find TextBlockRenderBox
  → Convert global→local coordinates
  → Get segment index and offset
  → UserInputService.handleDragStart(pageId, blockId, segIdx, offset)
→ PageSelectionSubsystem.setRangeSelection(...)
  → Set page.selection.value = RangeSelectionEntity
→ User drags mouse
→ PageEditorWidget._onPointerMove(event)
  → Hit-test new position
  → UserInputService.handleDragUpdate(...)
→ PageSelectionSubsystem updates extent
→ BlockEditorWidget rebuilds
→ computeBlockSelectionInfo() computes role per block
→ TextBlockRenderBox paints selection highlight
→ User releases mouse
→ PageEditorWidget._onPointerUp(event)
  → UserInputService.handleDragEnd(pageId)
```

---

## Testing

**Test Coverage:**
- Entity tests: `test/lib/entity/`
- System tests: `test/lib/systems/`
  - `page_system/page_editing_subsystem_test.dart`
  - `page_system/page_frontmatter_codec_test.dart`
  - `markdown_system/markdown_system_test.dart`
  - `vault/vault_system_test.dart`
  - `vault/vault_repository_test.dart`
- Widget tests: `test/lib/view/widgets/editor/compute_block_selection_info_test.dart`

**Test Approach:**
- Unit tests for entities and systems
- Fake implementations for services (e.g., `FakeFileSystemService`)
- Pure function tests (e.g., `computeBlockSelectionInfo`)
- No widget tests for UI (yet)

**Running Tests:**
```bash
flutter test
```

---

## What's NOT Implemented Yet

### Persistence
- ❌ Autosave (only manual Ctrl+S)
- ❌ WAL (Write-Ahead Log) for crash recovery
- ❌ Session restore (reopen last documents)
- ❌ Dirty state tracking

### Sync
- ❌ Oplog (operation log)
- ❌ File watchers
- ❌ Merge engine
- ❌ Conflict resolution

### UI Features
- ❌ File create/rename/delete from UI
- ❌ Undo/Redo
- ❌ Formatting toolbar
- ❌ Mobile touch gestures optimization
- ❌ Journal panel content
- ❌ Bookmarks panel content
- ❌ Settings panel content

### Advanced Editor
- ❌ Non-text blocks (headers, tasks, lists, code blocks)
- ❌ Block-level operations (move, duplicate, delete)
- ❌ Drag-and-drop block reordering
- ❌ Multi-cursor support

---

## Comparison with ARCHITECTURE.md

| Aspect | ARCHITECTURE.md (Vision) | Current State |
|--------|--------------------------|---------------|
| **Vault structure** | `.noetec/device.json`, `.sync/`, WAL | Simplified: `.noetec/vault.json`, no `.sync/`, no WAL |
| **Frontmatter** | Includes `modified_by` (device UUID) | Simplified: no `modified_by` (no device identity yet) |
| **Save strategy** | Autosave + WAL + manual Ctrl+S | Manual Ctrl+S only |
| **Sync** | Full oplog + merge engine | Not implemented |
| **Block types** | Headers, tasks, lists, code blocks | Text blocks only |
| **Systems** | 7 systems (Navigation, Markdown, Editor, Vault, Persistence, Oplog, Sync) | 5 systems (Layout, Markdown, Page, UserInput, Vault) |
| **Naming** | Document-centric | Page-centric (PageSystem vs DocumentSystem) |

**Key Differences:**
1. **Simplified MVP**: Current implementation is a minimal viable product, focusing on core editing workflow
2. **No device identity**: `modified_by` field dropped until sync is implemented
3. **No autosave**: Manual save only, no WAL or crash recovery
4. **No sync**: Oplog, merge engine, file watchers not implemented
5. **Text blocks only**: No support for other block types yet

---

## Next Steps

Based on the current state, the next logical steps would be:

1. **Autosave + WAL** — Implement debounced autosave and write-ahead log for crash recovery
2. **Session restore** — Remember open tabs and restore on app restart
3. **File management UI** — Create/rename/delete files and folders from UI
4. **Undo/Redo** — Command history with undo/redo support
5. **Additional block types** — Headers, tasks, lists, code blocks
6. **Oplog engine** — Record block-level operations for sync
7. **File watchers** — Detect external file changes
8. **Merge engine** — 3-way merge with conflict resolution

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full implementation roadmap.
