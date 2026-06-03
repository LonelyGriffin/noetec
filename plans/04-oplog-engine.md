# Этап 4: Operation Log Engine

## Цель

Каждое сохранение документа создаёт запись в oplog для этого устройства.
Oplog хранит block-level diff операции с HLC timestamps и parent ссылками,
формируя DAG изменений, готовый к синхронизации в этапе 5.

**После этого этапа:** история изменений каждого файла полностью записана
в `.sync/vault/<path>/<device>.oplog.jsonl`. Можно полностью восстановить
любое прошлое состояние документа из oplog.

**Зависимость:** Этапы 1-3 завершены.

---

## 1. Модели операций

### 1.1. BlockOp — операция над конкретным блоком

Файл: `lib/OplogSystem/models/block_op.dart`

```dart
sealed class BlockOp {}

class BlockInsert extends BlockOp {
  final String blockId;          // ID нового блока
  final String? afterBlockId;    // null = вставить в начало
  final String blockType;        // 'text' (на будущее: 'heading', 'code', 'list')
  final List<Map<String, dynamic>> segments; // сериализованные TextSegment
}

class BlockDelete extends BlockOp {
  final String blockId;
}

class BlockUpdate extends BlockOp {
  final String blockId;
  final List<Map<String, dynamic>> segments; // новые segments
}

class BlockMove extends BlockOp {
  final String blockId;
  final String? afterBlockId;    // null = переместить в начало
}
```

### 1.2. FileOp — мета-операция над файлом

Файл: `lib/OplogSystem/models/file_op.dart`

```dart
sealed class FileOp {}

class FileCreate extends FileOp {
  final String documentId;       // UUID из frontmatter
  final List<BlockOp> initialBlocks; // начальные блоки (обычно один пустой)
}

class FileDelete extends FileOp {}

class FileRename extends FileOp {
  final String oldRelativePath;
  final String newRelativePath;
}
```

### 1.3. OpLogEntry — одна запись в oplog

Файл: `lib/OplogSystem/models/oplog_entry.dart`

```dart
class OpLogEntry {
  final int version;             // Версия формата, сейчас = 1
  final Hlc hlc;                 // HLC timestamp этой операции
  final Hlc? parent;             // HLC предыдущей операции (null для file_create)
  final OpEntryType type;        // Тип верхнеуровневой записи
  final List<BlockOp>? blockOps; // Для type=edit: список block-level изменений
  final FileOp? fileOp;          // Для type=file_*: мета операция
  final String? fileHash;        // SHA-256 snapshot для type=save
  final String? deviceId;        // UUID устройства-автора (для удобства)
}

enum OpEntryType {
  fileCreate,      // Создание файла
  fileDelete,      // Удаление файла
  fileRename,      // Переименование
  edit,            // Редактирование (список BlockOp)
  save,            // Точка сохранения (file_hash)
  externalEdit,    // Внешнее изменение (file_hash + полные блоки)
  merge,           // Объединение веток (parent_a, parent_b)
}
```

---

## 2. Сериализация BlockOp / OpLogEntry

Файл: `lib/OplogSystem/oplog_serializer.dart`

Каждый `OpLogEntry` → одна строка JSON.

### Примеры JSON записей

**file_create:**
```json
{"v":1,"hlc":"1705312200000-0000-a1b2c3d4","parent":null,"type":"file_create","device":"a1b2c3d4-5678-90ab-cdef-1234567890ab","file_op":{"document_id":"f47ac10b-58cc","initial_blocks":[{"id":"block-001","type":"text","segments":[{"text":"","format":0}]}]}}
```

**edit (block_update + block_insert):**
```json
{"v":1,"hlc":"1705312201000-0001-a1b2c3d4","parent":"1705312200000-0000-a1b2c3d4","type":"edit","device":"a1b2c3d4-...","block_ops":[{"op":"block_update","block_id":"block-001","segments":[{"text":"Hello world","format":0}]},{"op":"block_insert","block_id":"block-002","after_block_id":"block-001","block_type":"text","segments":[{"text":"","format":0}]}]}
```

**save:**
```json
{"v":1,"hlc":"1705312205000-0002-a1b2c3d4","parent":"1705312201000-0001-a1b2c3d4","type":"save","device":"a1b2c3d4-...","file_hash":"sha256:e3b0c44298fc1c149afbf4c8996fb924"}
```

### Сериализация TextSegment

```json
{"text": "Hello", "format": 0}               // PlainSegment
{"text": "bold", "format": 1}                // Bold (bitmask)
{"text": "italic", "format": 2}              // Italic
{"text": "bolditalic", "format": 3}          // Bold + Italic
{"text": "link text", "format": 0, "url": "https://example.com"}  // LinkSegment
```

---

## 3. BlockDiffEngine

Файл: `lib/OplogSystem/block_diff_engine.dart`

Вычисляет минимальный список `BlockOp` между двумя состояниями документа.

### Вход/Выход

```dart
class BlockDiffEngine {
  // Вычислить diff между предыдущим и текущим состоянием блоков.
  // Возвращает пустой список если изменений нет.
  static List<BlockOp> compute(
    List<TextBlock> previous,  // состояние до изменений
    List<TextBlock> current,   // состояние после изменений
  );
}
```

### Алгоритм

Используем подход LCS (Longest Common Subsequence) по block ID для
определения вставок/удалений, и прямое сравнение для обновлений:

```
1. Построить Map<id, TextBlock> для previous и current

2. Определить deleted: id в previous, нет в current
   → BlockDelete для каждого

3. Определить inserted: id в current, нет в previous
   → BlockInsert для каждого (с after_block_id по позиции в current)

4. Определить updated: id есть в обоих, но содержимое изменилось
   → Сравнить segments (по тексту и формату)
   → BlockUpdate если отличаются

5. Определить moved: id есть в обоих, содержимое то же, позиция изменилась
   → BlockMove с новым after_block_id

6. Порядок применения ops при replay:
   - Сначала BlockDelete (освобождаем ID)
   - Затем BlockInsert (в порядке current)
   - Затем BlockUpdate
   - Затем BlockMove
```

**Сравнение segments:** два блока считаются одинаковыми если:
- Одинаковое количество segments
- Каждый segment: одинаковый text, format и url (если есть)

---

## 4. OpLogWriter

Файл: `lib/OplogSystem/oplog_writer.dart`

Записывает oplog entries в `.sync/vault/<relativePath>/<device-uuid>.oplog.jsonl`.

```dart
class OpLogWriter {
  // Записать edit запись.
  // Вызывается при каждом save (из DocumentPersistenceService.save())
  // если есть изменения (blockOps не пустой).
  Future<void> writeEdit(
    String relativePath,
    List<BlockOp> blockOps,
    Hlc hlc,
    Hlc? parentHlc,
  );

  // Записать save запись (точка сохранения с file_hash).
  // Вызывается после записи edit, всегда.
  Future<void> writeSave(
    String relativePath,
    String fileHash,
    Hlc hlc,
    Hlc? parentHlc,
  );

  // Записать file_create запись (при создании нового файла).
  Future<void> writeFileCreate(
    String relativePath,
    String documentId,
    List<TextBlock> initialBlocks,
    Hlc hlc,
  );

  // Записать file_delete запись.
  Future<void> writeFileDelete(String relativePath, Hlc hlc, Hlc? parentHlc);

  // Записать file_rename запись.
  Future<void> writeFileRename(
    String oldRelativePath,
    String newRelativePath,
    Hlc hlc,
    Hlc? parentHlc,
  );

  // Записать external_edit запись (при обнаружении внешнего изменения).
  Future<void> writeExternalEdit(
    String relativePath,
    List<TextBlock> currentBlocks,
    String fileHash,
    Hlc hlc,
    Hlc? parentHlc,
  );
}
```

### Путь к oplog файлу

```dart
String oplogPath(String vaultRoot, String relativePath, String deviceUuid) {
  return '$vaultRoot/.sync/vault/$relativePath/$deviceUuid.oplog.jsonl';
}
```

### Отслеживание "предыдущего состояния" для diff

`OpLogWriter` хранит `Map<documentId, List<TextBlock>> _lastKnownState`.

При `writeEdit()`:
- `_lastKnownState[documentId]` — предыдущее состояние
- После записи: обновить `_lastKnownState[documentId] = current`

При `writeFileCreate()`: `_lastKnownState[documentId] = initialBlocks`

### Отслеживание "последнего parent HLC"

`OpLogWriter` хранит `Map<String, Hlc> _lastHlcByFile` (relativePath → последний HLC).

При каждой записи: обновить `_lastHlcByFile[relativePath]` из нового HLC.

---

## 5. OpLogReader

Файл: `lib/OplogSystem/oplog_reader.dart`

```dart
class OpLogReader {
  // Прочитать oplog одного устройства для файла
  Future<List<OpLogEntry>> readDeviceLog(
    String vaultRoot,
    String relativePath,
    String deviceUuid,
  );

  // Прочитать все oplog файлы для файла (все устройства)
  Future<Map<String, List<OpLogEntry>>> readAllLogs(
    String vaultRoot,
    String relativePath,
  );

  // Получить список устройств у которых есть oplog для файла
  Future<List<String>> getDeviceUuids(String vaultRoot, String relativePath);
}
```

---

## 6. OpLogDag

Файл: `lib/OplogSystem/oplog_dag.dart`

Строит ориентированный ациклический граф операций из нескольких oplog файлов.

```dart
class OpLogDag {
  // Построить DAG из операций всех устройств
  factory OpLogDag.fromEntries(Map<String, List<OpLogEntry>> entriesByDevice);

  // Найти heads (последние операции каждого устройства)
  Map<String, OpLogEntry> get heads;

  // Проверить топологию: одна линия или ветвление?
  DagTopology get topology;

  // Найти LCA (Lowest Common Ancestor) двух heads
  // Используется для 3-way merge в этапе 5
  OpLogEntry? lca(OpLogEntry a, OpLogEntry b);

  // Получить все операции от ancestor до head (в хронологическом порядке)
  List<OpLogEntry> pathFrom(OpLogEntry ancestor, OpLogEntry head);

  // Порядок операций: топологическая сортировка по HLC
  List<OpLogEntry> get sortedEntries;
}

enum DagTopology {
  empty,         // Нет операций
  single,        // Только один head
  linear,        // Все heads на одной линии (fast-forward возможен)
  diverged,      // Heads расходятся (нужен merge)
}
```

### Построение DAG

```
1. Собрать все OpLogEntry из всех устройств
2. Создать Map<HlcKey, OpLogEntry> для быстрого lookup
3. Граф: OpLogEntry → parent (по parent HLC)
4. Heads: entries у которых нет дочерних (нет entry с parent = этот)
5. LCA: обычный алгоритм LCA через BFS/DFS по parent ссылкам
```

---

## 7. StateReconstructionEngine

Файл: `lib/OplogSystem/state_reconstruction_engine.dart`

Восстанавливает состояние документа из цепочки операций.

```dart
class StateReconstructionEngine {
  // Восстановить состояние в заданной точке DAG.
  // Обходит DAG от file_create до указанного entry,
  // применяя BlockOp'ы последовательно.
  static Future<List<TextBlock>> reconstruct(
    OpLogDag dag,
    OpLogEntry targetEntry,
    IdService idService,
  );

  // Применить один OpLogEntry к текущему состоянию
  static List<TextBlock> applyEntry(
    List<TextBlock> state,
    OpLogEntry entry,
    IdService idService,
  );

  // Применить один BlockOp к списку блоков
  static List<TextBlock> applyBlockOp(
    List<TextBlock> blocks,
    BlockOp op,
    IdService idService,
  );
}
```

### Алгоритм applyBlockOp

```
BlockInsert:
  - Создать новый TextBlock с заданным blockId и segments
  - Найти позицию afterBlockId (или начало если null)
  - Вставить блок после указанного

BlockDelete:
  - Найти блок по blockId
  - Удалить из списка

BlockUpdate:
  - Найти блок по blockId
  - Заменить segments на новые

BlockMove:
  - Найти блок по blockId
  - Удалить с текущей позиции
  - Вставить после afterBlockId (или в начало)
```

---

## 8. Интеграция с DocumentPersistenceService

Файл: `lib/PersistenceSystem/document_persistence_service.dart` (изменение)

В методе `save(documentId)` после записи файла:

```dart
// Этап 4: записать oplog
final currentBlocks = document.rootBlocks.value;
final previousBlocks = di<OpLogWriter>().getLastKnownState(documentId);

final diff = BlockDiffEngine.compute(previousBlocks, currentBlocks);

final hlc = di<HlcService>().now();
final parentHlc = di<OpLogWriter>().getLastHlc(relativePath);

if (diff.isNotEmpty) {
  await di<OpLogWriter>().writeEdit(relativePath, diff, hlc, parentHlc);
  hlc = di<HlcService>().now();  // Получить следующий HLC для save записи
}

await di<OpLogWriter>().writeSave(
  relativePath,
  VaultService.computeContentHash(content),
  hlc,
  diff.isNotEmpty ? hlc : parentHlc,
);
```

---

## 9. Верификация integrity

При replay oplog до конца:
- Последняя `save` запись содержит `file_hash`
- Восстановленное состояние сериализуется в markdown → вычислить hash
- Если не совпадает → предупредить пользователя (возможно повреждённый oplog)

---

## 10. Структура новых файлов

```
lib/
└── OplogSystem/
    ├── models/
    │   ├── block_op.dart
    │   ├── file_op.dart
    │   └── oplog_entry.dart
    ├── oplog_serializer.dart
    ├── block_diff_engine.dart
    ├── oplog_writer.dart
    ├── oplog_reader.dart
    ├── oplog_dag.dart
    └── state_reconstruction_engine.dart
```

Изменения в существующих файлах:
- `lib/PersistenceSystem/document_persistence_service.dart` — вызов OpLogWriter при save
- `lib/VaultSystem/vault_service.dart` — вызов OpLogWriter при createFile/deleteFile/renameFile
- `lib/configure_di.dart` — регистрация OpLogWriter, OpLogReader

---

## 11. Тесты

| Тест | Файл |
|---|---|
| BlockDiffEngine: нет изменений → пустой diff | `test/OplogSystem/block_diff_engine_test.dart` |
| BlockDiffEngine: update одного блока | `test/OplogSystem/block_diff_engine_test.dart` |
| BlockDiffEngine: insert нового блока | `test/OplogSystem/block_diff_engine_test.dart` |
| BlockDiffEngine: delete блока | `test/OplogSystem/block_diff_engine_test.dart` |
| BlockDiffEngine: move блока | `test/OplogSystem/block_diff_engine_test.dart` |
| OplogSerializer: round-trip для каждого типа | `test/OplogSystem/oplog_serializer_test.dart` |
| StateReconstructionEngine: replay из file_create | `test/OplogSystem/state_reconstruction_engine_test.dart` |
| StateReconstructionEngine: replay insert+update+delete | `test/OplogSystem/state_reconstruction_engine_test.dart` |
| OpLogDag: построение из двух устройств | `test/OplogSystem/oplog_dag_test.dart` |
| OpLogDag: определение topology (linear vs diverged) | `test/OplogSystem/oplog_dag_test.dart` |
| OpLogDag: нахождение LCA | `test/OplogSystem/oplog_dag_test.dart` |
| OpLogWriter: файл создаётся и содержит корректный JSON | `test/OplogSystem/oplog_writer_test.dart` |
| Integration: save → oplog written → reconstruct = original | `test/integration/oplog_round_trip_test.dart` |

---

## 12. Критерии готовности этапа

- [ ] При создании файла записывается `file_create` запись в oplog
- [ ] При каждом сохранении записывается `edit` (если есть изменения) + `save`
- [ ] При удалении файла записывается `file_delete` в oplog
- [ ] При переименовании записывается `file_rename` в oplog
- [ ] `BlockDiffEngine.compute()` корректно вычисляет diff для всех типов изменений
- [ ] `StateReconstructionEngine.reconstruct()` воспроизводит исходное состояние из oplog
- [ ] `OpLogDag` корректно определяет topology и находит LCA
- [ ] SHA-256 hash восстановленного состояния совпадает с `file_hash` в `save` записи
- [ ] Все существующие тесты проходят
