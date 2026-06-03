# Этап 5: Sync Engine и Merge

## Цель

Обнаруживать изменения от других устройств в `.sync/vault/` и сливать их
с локальным состоянием. Обнаруживать внешние правки файлов в `vault/`.
Предоставить UI для ручного разрешения конфликтов.

**После этого этапа:** vault синхронизируется между устройствами через
любой file sync сервис (Dropbox, iCloud Drive, Syncthing и т.д.).

**Зависимость:** Этапы 1-4 завершены.

---

## 1. Два потока мониторинга

### 1.1. SyncWatcher — наблюдение за `.sync/vault/`

Файл: `lib/SyncSystem/sync_watcher.dart`

Обнаруживает появление новых oplog записей от других устройств
(после того как Dropbox/iCloud синхронизировал файлы).

```dart
class SyncWatcher {
  // Запустить polling с интервалом (default 10 секунд)
  void start({Duration interval = const Duration(seconds: 10)});
  void stop();

  // Stream событий: файл изменился у другого устройства
  Stream<SyncChangeEvent> get changes;
}

class SyncChangeEvent {
  final String relativePath;         // Путь к документу (в vault/)
  final String deviceUuid;           // Устройство, у которого изменился oplog
  final int newEntriesCount;         // Сколько новых записей появилось
}
```

### Алгоритм polling

При каждом тике:
1. Рекурсивно обойти `.sync/vault/`
2. Для каждой папки (= один документ):
   - Для каждого `<device-uuid>.oplog.jsonl`:
     - Получить `File.lastModifiedSync()`
     - Сравнить с кешированным значением (Map в памяти: path → lastModified)
     - Если изменился → добавить в список changed
3. Отправить `SyncChangeEvent` для каждого changed
4. Обновить кеш

**Исключать:** oplog файл текущего устройства (его мы сами пишем).

### 1.2. VaultWatcher — наблюдение за `vault/`

Файл: `lib/SyncSystem/vault_watcher.dart`

Обнаруживает внешние правки .md файлов другими редакторами.

```dart
class VaultWatcher {
  void start({Duration interval = const Duration(seconds: 30)});
  void stop();

  // Stream событий: файл изменён внешним инструментом
  Stream<ExternalEditEvent> get edits;
}

class ExternalEditEvent {
  final String relativePath;
  final String currentHash;    // Реальный hash содержимого
  final String knownHash;      // Hash из frontmatter (устаревший)
}
```

### Алгоритм polling для VaultWatcher

При каждом тике:
1. Обойти все .md файлы в `vault/`
2. Для каждого файла:
   - Прочитать frontmatter (только yaml-блок, не весь файл)
   - Вычислить hash содержимого после frontmatter
   - Сравнить с `frontmatter.content_hash`
   - Если не совпадает → отправить `ExternalEditEvent`

**Оптимизация:** сначала проверять `File.lastModifiedSync()` против
кеша. Если lastModified не изменился — skip (не читаем содержимое).

---

## 2. SyncService — оркестратор синхронизации

Файл: `lib/SyncSystem/sync_service.dart`

```dart
class SyncService {
  // Запустить наблюдение (вызывается при открытии vault)
  Future<void> start(String vaultRootPath);
  Future<void> stop();

  // ValueNotifier: общий статус синхронизации
  ValueNotifier<SyncStatus> get status;

  // Map: relativePath → DocumentSyncState
  // Для отображения иконок в sidebar
  Map<String, ValueNotifier<DocumentSyncState>> get documentStates;

  // Принудительно проверить конкретный файл
  Future<void> checkFile(String relativePath);

  // Принудительно проверить все файлы
  Future<void> checkAll();
}

enum SyncStatus {
  idle,        // Нет ожидающих изменений
  checking,    // Идёт проверка
  merging,     // Идёт merge
  conflict,    // Есть неразрешённые конфликты
  error,       // Ошибка при синхронизации
}

enum DocumentSyncState {
  synced,      // Нет изменений от других устройств
  pending,     // Есть изменения, merge ещё не запущен
  merging,     // Идёт merge
  conflict,    // Есть неразрешимый конфликт
  diverged,    // Есть изменения, успешно смерджены (transient)
}
```

---

## 3. MergeEngine

Файл: `lib/SyncSystem/merge_engine.dart`

核心 алгоритм синхронизации.

```dart
class MergeEngine {
  // Основная точка входа.
  // Принимает DAG с несколькими heads, возвращает результат merge.
  Future<MergeResult> merge(
    String relativePath,
    OpLogDag dag,
    String ourDeviceUuid,
  );
}

sealed class MergeResult {}

// Всё смерджено автоматически — обновить snapshot файл
class MergeSuccess extends MergeResult {
  final List<TextBlock> mergedBlocks;
  final List<OpLogEntry> appliedEntries; // entries которые мы применили
}

// Есть конфликты требующие ручного разрешения
class MergeConflict extends MergeResult {
  final List<BlockConflict> conflicts;
  final List<TextBlock> partiallyMergedBlocks; // блоки без конфликтов уже смерджены
}

// Только fast-forward — просто применить новые entries
class MergeFastForward extends MergeResult {
  final List<TextBlock> updatedBlocks;
}
```

### Алгоритм merge

```dart
Future<MergeResult> merge(relativePath, dag, ourDeviceUuid) {
  // 1. Проверить топологию DAG
  if (dag.topology == DagTopology.single || dag.topology == DagTopology.empty)
    return MergeFastForward(dag.reconstructAtHead(ourDeviceUuid));

  // 2. Если linear → fast-forward
  if (dag.topology == DagTopology.linear) {
    final globalHead = dag.getLinearHead();
    final mergedBlocks = StateReconstructionEngine.reconstruct(dag, globalHead);
    return MergeFastForward(mergedBlocks);
  }

  // 3. Diverged → 3-way merge
  final ourHead = dag.heads[ourDeviceUuid];
  final theirHeads = dag.heads.values.where((h) => h.device != ourDeviceUuid);

  // Для каждой пары (ours, theirs) выполнить 3-way merge
  // Если несколько чужих устройств — применять по очереди
  var currentBlocks = StateReconstructionEngine.reconstruct(dag, ourHead);
  final conflicts = <BlockConflict>[];

  for (final theirHead in theirHeads) {
    final ancestor = dag.lca(ourHead, theirHead);
    final ancestorBlocks = StateReconstructionEngine.reconstruct(dag, ancestor);
    final theirBlocks = StateReconstructionEngine.reconstruct(dag, theirHead);

    final result = _threeWayMerge(ancestorBlocks, currentBlocks, theirBlocks);
    currentBlocks = result.merged;
    conflicts.addAll(result.conflicts);
  }

  if (conflicts.isEmpty)
    return MergeSuccess(mergedBlocks: currentBlocks, ...);
  else
    return MergeConflict(conflicts: conflicts, partiallyMergedBlocks: currentBlocks);
}
```

### 3-way merge на уровне блоков

```dart
_ThreeWayBlockMergeResult _threeWayMerge(
  List<TextBlock> ancestor,
  List<TextBlock> ours,
  List<TextBlock> theirs,
) {
  // Работаем с блоками по ID

  final ancestorIds = ancestor.map((b) => b.id).toSet();
  final ourIds = ours.map((b) => b.id).toSet();
  final theirIds = theirs.map((b) => b.id).toSet();

  final merged = <TextBlock>[];
  final conflicts = <BlockConflict>[];

  // Удалённые с нашей стороны: в ancestor, нет в ours
  final deletedByUs = ancestorIds.difference(ourIds);

  // Удалённые с их стороны: в ancestor, нет в theirs
  final deletedByThem = ancestorIds.difference(theirIds);

  // Вставленные с нашей стороны: нет в ancestor, есть в ours
  final insertedByUs = ourIds.difference(ancestorIds);

  // Вставленные с их стороны: нет в ancestor, есть в theirs
  final insertedByThem = theirIds.difference(ancestorIds);

  // Блоки существующие в обоих (возможно изменённые)
  final commonInBoth = ourIds.intersection(theirIds);

  for (final id in _mergedOrder(ancestor, ours, theirs)) {
    // Удалён обоими → пропустить (согласны)
    if (deletedByUs.contains(id) && deletedByThem.contains(id)) continue;

    // Удалён нами, изменён ими → конфликт delete/modify
    if (deletedByUs.contains(id) && theirIds.contains(id)) {
      final theirBlock = theirs.firstWhere((b) => b.id == id);
      final ancestorBlock = ancestor.firstWhere((b) => b.id == id);
      if (!_blocksEqual(theirBlock, ancestorBlock)) {
        // Они изменили, мы удалили → добавить их версию + пометить конфликт
        conflicts.add(BlockConflict.deleteModify(id, theirBlock));
        merged.add(theirBlock); // По умолчанию: сохранить изменённую версию
      }
      // Если они не изменили — удаление консистентно, пропустить
      continue;
    }

    // Удалён ими, изменён нами → зеркальный конфликт
    if (deletedByThem.contains(id) && ourIds.contains(id)) {
      final ourBlock = ours.firstWhere((b) => b.id == id);
      final ancestorBlock = ancestor.firstWhere((b) => b.id == id);
      if (!_blocksEqual(ourBlock, ancestorBlock)) {
        conflicts.add(BlockConflict.deleteModify(id, ourBlock));
        merged.add(ourBlock); // По умолчанию: сохранить нашу версию
      }
      continue;
    }

    // Вставлен только нами или только ими → нет конфликта
    if (insertedByUs.contains(id)) { merged.add(ours.firstWhere((b)=>b.id==id)); continue; }
    if (insertedByThem.contains(id)) { merged.add(theirs.firstWhere((b)=>b.id==id)); continue; }

    // Существует в обоих — сравниваем содержимое
    final ourBlock = ours.firstWhere((b) => b.id == id);
    final theirBlock = theirs.firstWhere((b) => b.id == id);
    final ancestorBlock = ancestor.firstWhere((b) => b.id == id, orElse: () => null);

    final changedByUs   = ancestorBlock != null && !_blocksEqual(ourBlock, ancestorBlock);
    final changedByThem = ancestorBlock != null && !_blocksEqual(theirBlock, ancestorBlock);

    if (!changedByUs && !changedByThem) { merged.add(ourBlock); continue; }
    if (changedByUs && !changedByThem)  { merged.add(ourBlock); continue; }
    if (!changedByUs && changedByThem)  { merged.add(theirBlock); continue; }

    // Оба изменили — попробовать line-level merge содержимого
    final lineMergeResult = _lineLevelMerge(ancestorBlock!, ourBlock, theirBlock);
    if (lineMergeResult.success) {
      merged.add(lineMergeResult.block);
    } else {
      conflicts.add(BlockConflict.contentConflict(id, ourBlock, theirBlock));
      merged.add(_createConflictBlock(id, ourBlock, theirBlock));
    }
  }

  return _ThreeWayBlockMergeResult(merged: merged, conflicts: conflicts);
}
```

### Line-level merge

Для блока, изменённого обоими: разбить текст на строки и применить diff3.

```dart
_LineMergeResult _lineLevelMerge(TextBlock ancestor, TextBlock ours, TextBlock theirs) {
  final ancestorText = ancestor.computeAllSegmentsText();
  final ourText = ours.computeAllSegmentsText();
  final theirText = theirs.computeAllSegmentsText();

  final ancestorLines = ancestorText.split('\n');
  final ourLines = ourText.split('\n');
  final theirLines = theirText.split('\n');

  // diff3 алгоритм: найти изменённые строки в ours и theirs относительно ancestor
  // Если изменённые строки не пересекаются → автоматический merge
  // Если пересекаются → конфликт

  // Реализация через простой LCS-based diff3
  // ...
}
```

### Conflict marker

Если line-level merge не удался, создать блок с conflict marker:

```dart
TextBlock _createConflictBlock(String id, TextBlock ours, TextBlock theirs) {
  // Создать блок с текстом:
  // <<<< ours
  // <наш текст>
  // ====
  // <их текст>
  // >>>> theirs
  //
  // Форматирование: весь marker моноширинным/особым стилем (будущее)
}
```

---

## 4. Обработка внешних правок (ExternalEditEvent)

Файл: `lib/SyncSystem/external_edit_handler.dart`

```dart
class ExternalEditHandler {
  Future<void> handle(ExternalEditEvent event) async {
    // 1. Прочитать текущее содержимое файла
    final ({frontmatter, content}) = await vaultService.readFile(event.relativePath);
    final currentBlocks = markdownToBlocks(content);

    // 2. Получить последнее известное состояние из oplog
    final dag = OpLogDag.fromEntries(
      await oplogReader.readAllLogs(vaultRoot, event.relativePath)
    );
    final lastKnownBlocks = dag.topology == DagTopology.empty
        ? <TextBlock>[]
        : StateReconstructionEngine.reconstruct(dag, dag.heads[ourDeviceUuid]!);

    // 3. Записать external_edit запись в oplog
    await oplogWriter.writeExternalEdit(
      event.relativePath,
      currentBlocks,
      event.currentHash,
      hlcService.now(),
      dag.heads[ourDeviceUuid]?.hlc,
    );

    // 4. Обновить frontmatter.content_hash
    await vaultService.writeFile(
      event.relativePath,
      blocksToMarkdown(currentBlocks),
      deviceUuid,
    );

    // 5. Если документ открыт в редакторе — уведомить пользователя
    final openDoc = openedDocumentsManager.getByPath(event.relativePath);
    if (openDoc != null) {
      // Показать notification: "File changed externally. Reload?"
      // Не перезаписывать in-memory state автоматически!
    }
  }
}
```

---

## 5. Применение merge результата

Файл: `lib/SyncSystem/merge_applier.dart`

После успешного merge:

```dart
class MergeApplier {
  Future<void> apply(String relativePath, MergeResult result) async {
    switch (result) {
      case MergeFastForward(:final updatedBlocks):
      case MergeSuccess(:final mergedBlocks):
        // 1. Записать merge операцию в oplog
        await oplogWriter.writeMerge(relativePath, mergedBlocks, ...);

        // 2. Сериализовать и записать snapshot в vault/
        final content = blocksToMarkdown(mergedBlocks);
        await vaultService.writeFile(relativePath, content, deviceUuid);

        // 3. Если документ открыт в редакторе — обновить in-memory модель
        final openDoc = openedDocumentsManager.getByPath(relativePath);
        if (openDoc != null) {
          _applyBlocksToDocument(openDoc, mergedBlocks);
        }

        // 4. Обновить documentStates
        syncService.documentStates[relativePath]?.value = DocumentSyncState.synced;

      case MergeConflict(:final conflicts, :final partiallyMergedBlocks):
        // Сохранить частичный merge (блоки без конфликтов)
        // Пометить документ как conflict
        syncService.documentStates[relativePath]?.value = DocumentSyncState.conflict;

        // Открыть ConflictResolutionView если документ активен
        // или показать badge/notification
    }
  }
}
```

---

## 6. Conflict Resolution UI

### 6.1. ConflictResolutionView

Файл: `lib/SyncSystem/conflict_resolution_view.dart`

Показывается когда документ имеет `DocumentSyncState.conflict`.

```
+--------------------------------------------------+
|  ⚠ Conflict in "today.md"         [Resolve All] |
+--------------------------------------------------+
| Block "paragraph-3" - Content conflict           |
|                                                  |
|  OURS (this device):                             |
|  ┌────────────────────────────────────────────┐  |
|  │ The quick brown fox jumps over             │  |
|  └────────────────────────────────────────────┘  |
|                                                  |
|  THEIRS (iPhone, 10:30):                         |
|  ┌────────────────────────────────────────────┐  |
|  └────────────────────────────────────────────┘  |
|  │ The quick brown fox leaps over             │  |
|  └────────────────────────────────────────────┘  |
|                                                  |
|  [Keep Ours]  [Keep Theirs]  [Keep Both]         |
+--------------------------------------------------+
```

### 6.2. BlockConflict модель

```dart
sealed class BlockConflict {}

class ContentConflict extends BlockConflict {
  final String blockId;
  final TextBlock ours;
  final TextBlock theirs;
  final String theirDeviceName;  // Для отображения "THEIRS (iPhone)"
  final DateTime theirTimestamp;
}

class DeleteModifyConflict extends BlockConflict {
  final String blockId;
  final TextBlock modifiedBlock;  // Изменённая версия
  final bool deletedByUs;         // true = мы удалили, они изменили
}
```

### 6.3. Разрешение конфликта

При выборе "Keep Ours" / "Keep Theirs" / "Keep Both":
1. Применить выбор к `partiallyMergedBlocks`
2. Создать `merge` запись в oplog (parent_a = ourHead, parent_b = theirHead)
3. Обновить snapshot файл
4. Перевести документ в `DocumentSyncState.synced`

---

## 7. Sync Status в UI

### 7.1. Иконки в FileTreeWidget

В `FileNodeWidget` показывать иконку состояния рядом с именем файла:

| DocumentSyncState | Иконка | Tooltip |
|---|---|---|
| `synced` | — (нет иконки) | |
| `pending` | 🔄 (маленький) | "Changes from other devices pending" |
| `merging` | ⏳ | "Merging..." |
| `conflict` | ⚠️ | "Conflict: manual resolution needed" |

### 7.2. Глобальный индикатор

В sidebar header:

```
| 📚 My Vault  ⚠2  [−] |
```

`⚠2` = 2 файла с конфликтами. Кликабельный → показать список конфликтных файлов.

---

## 8. Обработка открытого документа при merge

Когда merge приходит для документа, открытого в редакторе:

**Fast-forward / AutoMerge без конфликтов:**
- Если пользователь не редактировал с момента последнего save → применить тихо
- Если пользователь редактировал (dirty) → показать notification:
  `"This document was updated on another device. [Merge Now] [Later]"`
- `[Merge Now]` → save текущего состояния → writeEdit → runMerge → обновить редактор
- `[Later]` → merge отложен, иконка pending

**Конфликт:**
- Всегда уведомить явно
- `⚠ Conflict` кнопка в AppBar → открыть ConflictResolutionView

---

## 9. Структура новых файлов

```
lib/
└── SyncSystem/
    ├── sync_watcher.dart
    ├── vault_watcher.dart
    ├── sync_service.dart
    ├── merge_engine.dart
    ├── merge_applier.dart
    ├── external_edit_handler.dart
    └── conflict_resolution_view.dart
```

Изменения в существующих файлах:
- `lib/AppNavigation/app_root_widget.dart` — запуск SyncService при открытии vault
- `lib/Sidebar/file_tree_node_widget.dart` — иконки sync state
- `lib/DocumentView/document_app_bar_widget.dart` — кнопка conflict resolution
- `lib/configure_di.dart` — регистрация SyncService, MergeEngine, ExternalEditHandler

---

## 10. Тесты

| Тест | Файл |
|---|---|
| MergeEngine: fast-forward (linear dag) | `test/SyncSystem/merge_engine_test.dart` |
| MergeEngine: auto-merge разных блоков | `test/SyncSystem/merge_engine_test.dart` |
| MergeEngine: конфликт одного блока | `test/SyncSystem/merge_engine_test.dart` |
| MergeEngine: delete/modify конфликт | `test/SyncSystem/merge_engine_test.dart` |
| MergeEngine: line-level merge успешный | `test/SyncSystem/merge_engine_test.dart` |
| MergeEngine: line-level merge неудачный → conflict marker | `test/SyncSystem/merge_engine_test.dart` |
| SyncWatcher: обнаружение новых oplog файлов | `test/SyncSystem/sync_watcher_test.dart` |
| VaultWatcher: обнаружение external edit по hash | `test/SyncSystem/vault_watcher_test.dart` |
| Integration: два устройства, независимые изменения → auto-merge | `test/integration/sync_auto_merge_test.dart` |
| Integration: два устройства, конфликт → conflict state | `test/integration/sync_conflict_test.dart` |

---

## 11. Критерии готовности этапа

- [ ] SyncWatcher обнаруживает новые oplog файлы от других устройств (polling)
- [ ] VaultWatcher обнаруживает внешние правки через content_hash
- [ ] Fast-forward применяется автоматически и тихо
- [ ] Автоматический merge применяется для несовпадающих блоков
- [ ] Конфликты помечаются в sidebar (иконка ⚠️) и в AppBar
- [ ] ConflictResolutionView показывает обе версии блока
- [ ] После разрешения конфликта создаётся merge запись в oplog
- [ ] При merge документа открытого в редакторе — notification пользователю
- [ ] external_edit записывается в oplog при обнаружении внешней правки
- [ ] Все существующие тесты проходят
