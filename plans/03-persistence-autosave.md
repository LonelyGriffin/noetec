# Этап 3: Persistence, Autosave и Crash Recovery

## Цель

Документы сохраняются на диск и восстанавливаются при перезапуске.
Реализовать debounced autosave, WAL для crash recovery, session restoration.

**После этого этапа:** приложение является полноценным файловым редактором.
Данные не теряются ни при нормальном закрытии, ни при крэше.

**Зависимость:** Этапы 1 и 2 завершены.

---

## 1. DocumentPersistenceService

Файл: `lib/PersistenceSystem/document_persistence_service.dart`

Центральный сервис управления жизненным циклом документов (dirty state, save, autosave).

### Состояние документа

```dart
enum DocumentSaveState {
  clean,      // Совпадает с содержимым на диске
  dirty,      // Есть несохранённые изменения
  saving,     // В процессе записи на диск
  error,      // Ошибка при последнем сохранении
}
```

```dart
class DocumentPersistenceState {
  final DocumentSaveState saveState;
  final DateTime? lastSaved;
  final String? lastError;
}
```

### Интерфейс сервиса

```dart
class DocumentPersistenceService {
  // Карта: documentId → ValueNotifier<DocumentPersistenceState>
  // Для подписки в UI (индикатор состояния сохранения)
  Map<String, ValueNotifier<DocumentPersistenceState>> get states;

  // Пометить документ как изменённый.
  // Вызывается из UserActionService.dispatch() после каждого action.
  // Запускает autosave timer и WAL writer.
  void markDirty(String documentId);

  // Сохранить конкретный документ немедленно.
  // 1. DocumentLoader.saveDocument()
  // 2. Обновить lastSaved в state
  // 3. Очистить WAL для этого документа
  // 4. Перевести в DocumentSaveState.clean
  Future<void> save(String documentId);

  // Сохранить все dirty документы.
  Future<void> saveAll();

  // Зарегистрировать документ (при открытии)
  void register(String documentId, String relativePath);

  // Снять с учёта (при закрытии)
  void unregister(String documentId);
}
```

### Autosave timer

- При каждом `markDirty()`:
  - Отменить предыдущий timer
  - Запустить новый `Timer(Duration(seconds: 3), () => save(documentId))`
- При переключении на другой документ → `save(currentDocumentId)` немедленно
- При `AppLifecycleState.paused` (сворачивание) → `saveAll()`
- При `AppLifecycleState.detached` (закрытие) → `saveAll()`

---

## 2. Интеграция с UserActionSystem

### 2.1. Hook в UserActionService

Файл: `lib/UserActionSystem/user_action_service.dart` (изменение)

После диспатча каждого action:

```dart
Future<void> dispatch(UserAction action, DocumentModel document) async {
  // ... существующая логика ...

  // Новое: после успешного выполнения action
  di<DocumentPersistenceService>().markDirty(document.id);
  di<WalService>().appendAction(document.id, action);
}
```

### 2.2. Сериализация UserAction

Файл: `lib/PersistenceSystem/user_action_serializer.dart`

Каждый `UserAction` должен уметь сериализоваться в JSON и обратно.

```dart
// Пример сериализации
InsertText(documentId: 'd1', blockId: 'b1', flatOffset: 5, text: 'hello')
→ {"type":"insert_text","block_id":"b1","flat_offset":5,"text":"hello","ts":1705312200000}

SplitTextBlock(documentId: 'd1', blockId: 'b1', flatOffset: 10)
→ {"type":"split_text_block","block_id":"b1","flat_offset":10,"ts":1705312200000}
```

Поддерживаемые action типы для WAL (все, кроме навигационных):
`InsertText`, `DeleteTextBack`, `DeleteTextForward`, `ReplaceText`,
`SplitTextBlock`, `Paste`, `DeleteSelection`

Курсорные/selection actions (ClickOnTextBlock, MoveCursor и т.д.) в WAL НЕ пишутся
(они не изменяют содержимое).

---

## 3. WalService (Write-Ahead Log)

Файл: `lib/PersistenceSystem/wal_service.dart`

### Путь WAL файла

```
.noetec/wal/<encoded-path>.wal.jsonl
```

Кодирование пути: заменить `/` на `--` и убрать `.md` суффикс.
Пример: `notes/daily/2024-01-15.md` → `notes--daily--2024-01-15.wal.jsonl`

### Интерфейс

```dart
class WalService {
  // Добавить action в WAL. Debounced: группируем быстрый набор (250ms).
  // Для printable chars: не писать каждый символ отдельно,
  // а аккумулировать InsertText за 250ms и писать одну запись.
  void appendAction(String documentId, UserAction action);

  // Принудительный flush буфера (например перед save)
  Future<void> flush(String documentId);

  // Очистить WAL для документа (вызывается после успешного save)
  Future<void> clear(String documentId);

  // Очистить все WAL файлы (при нормальном закрытии)
  Future<void> clearAll();

  // Проверить есть ли незакрытые WAL файлы
  Future<List<WalEntry>> getPendingWals();

  // Прочитать WAL файл для документа
  Future<List<UserAction>> readWal(String relativePath);
}

class WalEntry {
  final String relativePath;
  final int actionCount;
  final DateTime lastModified;
}
```

### Формат WAL строки

Каждая строка — JSON с action + timestamp:

```json
{"ts":1705312200123,"type":"insert_text","block_id":"abc123","flat_offset":5,"text":"hello world"}
{"ts":1705312201000,"type":"split_text_block","block_id":"abc123","flat_offset":11}
{"ts":1705312201500,"type":"delete_text_back","block_id":"def456","flat_offset":3,"count":1}
```

### Debounce для InsertText

Быстрый набор текста порождает сотни InsertText событий в секунду.
Вместо записи каждого символа — аккумулировать в буфер 250ms:

```
InsertText(offset=0, text="h")
InsertText(offset=1, text="e")   →  (250ms пауза) → записать InsertText(offset=0, text="hello")
InsertText(offset=2, text="l")
InsertText(offset=3, text="l")
InsertText(offset=4, text="o")
```

Для DeleteTextBack/Forward: аналогично аккумулировать count.

---

## 4. Crash Recovery

### 4.1. CrashRecoveryService

Файл: `lib/PersistenceSystem/crash_recovery_service.dart`

```dart
class CrashRecoveryService {
  // Вызывается при запуске приложения.
  // Проверяет наличие .wal.jsonl файлов в .noetec/wal/
  // Возвращает список документов с незакрытыми WAL
  Future<List<RecoveryCandidate>> findCrashCandidates(String vaultRootPath);

  // Восстановить документ из crash:
  // 1. Загрузить последний сохранённый .md файл (через DocumentLoader)
  // 2. Применить действия из WAL поверх загруженного состояния
  // 3. Вернуть восстановленный DocumentModel
  Future<DocumentModel> recoverDocument(RecoveryCandidate candidate);
}

class RecoveryCandidate {
  final String relativePath;
  final List<UserAction> pendingActions;
  final DateTime walLastModified;
}
```

### 4.2. Сценарий при запуске

```
App start
  │
  ├─ CrashRecoveryService.findCrashCandidates()
  │    ├─ Нет WAL файлов → продолжить обычную загрузку
  │    └─ Есть WAL файлы
  │         ├─ Показать RecoveryDialog
  │         │    "The app was closed unexpectedly.
  │         │     Recover 2 unsaved documents?"
  │         │    [Discard] [Recover]
  │         │
  │         ├─ [Recover] → recoverDocument() для каждого
  │         │              → открыть с DocumentSaveState.dirty
  │         │              → пользователь видит "● Unsaved changes"
  │         └─ [Discard] → clearAll() WAL файлов
```

### 4.3. RecoveryDialog

Файл: `lib/PersistenceSystem/recovery_dialog.dart`

```
Crash Recovery
────────────────────────────────────
The app was closed unexpectedly.
The following documents have unsaved changes:

  • notes/daily/2024-01-15.md  (15 actions)
  • projects/noetec.md  (3 actions)

Would you like to recover them?

        [Discard]    [Recover]
```

---

## 5. Session Restoration

### 5.1. SessionService

Файл: `lib/PersistenceSystem/session_service.dart`

```dart
class SessionService {
  // Сохранить текущую сессию.
  // Вызывается при: смене активного документа, закрытии документа,
  // сворачивании приложения.
  Future<void> saveSession(SessionState state);

  // Загрузить последнюю сессию
  Future<SessionState?> loadSession(String vaultRootPath);

  // Очистить сессию
  Future<void> clearSession(String vaultRootPath);
}

class SessionState {
  final List<String> openDocumentPaths;    // Список открытых документов
  final String? activeDocumentPath;        // Активный документ
  final Map<String, SidebarState> sidebar; // Состояние sidebar (expanded folders)
}

class SidebarState {
  final Set<String> expandedFolders;       // relativePaths раскрытых папок
  final int sidebarWidth;                  // Ширина sidebar (desktop)
  final bool sidebarCollapsed;
}
```

### Файл session.json

Путь: `.noetec/session.json`

```json
{
  "open_documents": [
    "notes/daily/2024-01-15.md",
    "projects/noetec.md"
  ],
  "active_document": "notes/daily/2024-01-15.md",
  "sidebar": {
    "expanded_folders": ["notes", "notes/daily"],
    "width": 240,
    "collapsed": false
  }
}
```

### 5.2. Восстановление сессии при запуске

После crash recovery (или если не было краша):

```
App start (vault open)
  │
  ├─ SessionService.loadSession()
  │    ├─ Нет session.json → открыть пустой экран vault
  │    └─ Есть session.json
  │         ├─ Восстановить expanded folders в sidebar
  │         ├─ Открыть все open_documents (DocumentLoader)
  │         └─ Показать active_document в редакторе
```

---

## 6. Сохранение hash в frontmatter

Это ответственность `DocumentLoader.saveDocument()` и `VaultService.writeFile()`.

При каждом save:
1. `blocksToMarkdown(document.rootBlocks)` → `content` (без frontmatter)
2. `VaultService.computeContentHash(content)` → `hash`
3. Обновить `frontmatter.contentHash = hash`
4. Обновить `frontmatter.modified = DateTime.now()`
5. Обновить `frontmatter.modifiedBy = deviceUuid`
6. `DocumentFrontmatterCodec.encode(frontmatter, content)` → `fileContent`
7. Записать `fileContent` в `vault/<relativePath>`

---

## 7. Lifecycle integration

Файл: `lib/AppNavigation/app_root_widget.dart` (изменение)

Добавить `WidgetsBindingObserver` для отслеживания lifecycle:

```dart
class _AppRootWidgetState extends State<AppRootWidget>
    with WidgetsBindingObserver {

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        di<DocumentPersistenceService>().saveAll();
        di<SessionService>().saveSession(currentSession);
      case AppLifecycleState.resumed:
        // Можно проверить внешние изменения (этап 5)
        break;
      default:
        break;
    }
  }
}
```

---

## 8. UI: Индикатор состояния сохранения

Файл: `lib/DocumentView/document_app_bar_widget.dart` (изменение)

В AppBar справа:

```dart
class SaveStateIndicator extends WatchingWidget {
  final String documentId;

  @override
  Widget build(BuildContext context) {
    final state = watch(di<DocumentPersistenceService>().states[documentId]!);
    return switch (state.saveState) {
      DocumentSaveState.clean   => Icon(Icons.check, size: 14, color: Colors.grey),
      DocumentSaveState.dirty   => Text("●", style: TextStyle(color: Colors.orange)),
      DocumentSaveState.saving  => SizedBox(width: 14, height: 14,
                                     child: CircularProgressIndicator(strokeWidth: 1.5)),
      DocumentSaveState.error   => Icon(Icons.error_outline, size: 14, color: Colors.red),
    };
  }
}
```

Tooltip при hover: "Last saved: 10:30:05" или "Unsaved changes" или "Save error: ..."

---

## 9. Обработка Ctrl+S

Файл: `lib/UserInputSystem/handlers/keyboard_input_handler.dart` (изменение)

Добавить обработку `LogicalKeyboardKey.keyS` + ctrl:

```dart
if (keysPressed.contains(LogicalKeyboardKey.control) &&
    event.logicalKey == LogicalKeyboardKey.keyS) {
  di<DocumentPersistenceService>().save(currentDocumentId);
  return KeyEventResult.handled;
}
```

---

## 10. Структура новых файлов

```
lib/
└── PersistenceSystem/
    ├── document_persistence_service.dart
    ├── wal_service.dart
    ├── user_action_serializer.dart
    ├── crash_recovery_service.dart
    ├── recovery_dialog.dart
    └── session_service.dart
```

Изменения в существующих файлах:
- `lib/UserActionSystem/user_action_service.dart` — hook для markDirty + WAL
- `lib/UserInputSystem/handlers/keyboard_input_handler.dart` — Ctrl+S
- `lib/AppNavigation/app_root_widget.dart` — WidgetsBindingObserver
- `lib/configure_di.dart` — регистрация новых сервисов, crash recovery при запуске

---

## 11. Тесты

| Тест | Файл |
|---|---|
| DocumentPersistenceService: dirty tracking | `test/PersistenceSystem/document_persistence_service_test.dart` |
| DocumentPersistenceService: autosave timer | `test/PersistenceSystem/document_persistence_service_test.dart` |
| WalService: append, flush, clear | `test/PersistenceSystem/wal_service_test.dart` |
| WalService: debounce InsertText | `test/PersistenceSystem/wal_service_test.dart` |
| UserActionSerializer: round-trip для каждого типа | `test/PersistenceSystem/user_action_serializer_test.dart` |
| CrashRecoveryService: восстановление из WAL | `test/PersistenceSystem/crash_recovery_service_test.dart` |
| SessionService: save/load round-trip | `test/PersistenceSystem/session_service_test.dart` |
| Integration: InsertText → markDirty → WAL append → save → WAL clear | `test/integration/persistence_flow_test.dart` |

---

## 12. Критерии готовности этапа

- [ ] Изменения в документе автоматически сохраняются через 3 секунды
- [ ] Ctrl+S сохраняет немедленно
- [ ] Индикатор в AppBar корректно показывает clean / dirty / saving / error
- [ ] При сворачивании / закрытии приложения все документы сохраняются
- [ ] При симуляции крэша (kill process) изменения восстанавливаются через WAL
- [ ] RecoveryDialog показывается при наличии WAL файлов
- [ ] Последняя сессия восстанавливается при перезапуске (открытые документы + sidebar state)
- [ ] Content hash в frontmatter обновляется при каждом save
- [ ] Все существующие тесты проходят
