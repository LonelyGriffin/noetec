# Этап 1: Vault Foundation

## Цель

Создать базовую инфраструктуру для работы с vault как с файловой сущностью:
инициализация структуры папок, идентификация устройства, HLC, чтение/запись
.md файлов с YAML frontmatter, интеграция с существующим DocumentModel.

**После этого этапа:** приложение умеет создавать vault, создавать/читать/писать
.md файлы, загружать документ из файла в память и сохранять обратно.
UI пока не меняется (hardcoded документ переносится в vault).

---

## 1. Новые зависимости в pubspec.yaml

```yaml
dependencies:
  path_provider: ^2.1.4    # application documents directory
  crypto: ^3.0.3            # SHA-256 для content_hash
  yaml: ^3.1.2              # парсинг YAML frontmatter
  path: ^1.9.0              # уже есть в проекте
```

---

## 2. Модели данных

### 2.1. DeviceIdentity

Файл: `lib/VaultSystem/models/device_identity.dart`

```dart
class DeviceIdentity {
  final String uuid;          // UUID v4, генерируется один раз
  final String name;          // Пользовательское имя ("My MacBook", "Phone")
  final DateTime createdAt;
  String lastHlc;             // Последний выданный HLC (обновляется при каждой операции)
}
```

Хранится в `.noetec/device.json`:
```json
{
  "uuid": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
  "name": "My MacBook",
  "created_at": "2024-01-15T10:00:00.000Z",
  "last_hlc": "1705312200000-0001-a1b2c3d4"
}
```

### 2.2. VaultConfig

Файл: `lib/VaultSystem/models/vault_config.dart`

```dart
class VaultConfig {
  final String name;          // Отображаемое имя vault
  final DateTime createdAt;
  // Будущие настройки: тема, язык, autosave interval и т.д.
}
```

Хранится в `.noetec/config.json`.

### 2.3. FileTreeNode

Файл: `lib/VaultSystem/models/file_tree_node.dart`

```dart
sealed class FileTreeNode {
  final String name;           // Имя файла или папки (без пути)
  final String relativePath;   // Путь относительно vault/ (напр. "notes/daily/2024-01-15.md")
}

class FileNode extends FileTreeNode {
  final String documentId;     // UUID из frontmatter
  final DateTime? modified;    // из frontmatter
}

class FolderNode extends FileTreeNode {
  final List<FileTreeNode> children;  // ListNotifier для реактивности
}
```

### 2.4. DocumentFrontmatter

Файл: `lib/VaultSystem/models/document_frontmatter.dart`

```dart
class DocumentFrontmatter {
  final String id;             // UUID документа
  final String contentHash;   // sha256:<hex> от содержимого после frontmatter
  final DateTime modified;
  final String modifiedBy;    // UUID устройства
}
```

### 2.5. VaultInfo

Файл: `lib/VaultSystem/models/vault_info.dart`

```dart
class VaultInfo {
  final String rootPath;       // Абсолютный путь к корню vault
  final VaultConfig config;
  final DeviceIdentity device;
}
```

---

## 3. HybridLogicalClock

Файл: `lib/VaultSystem/hlc.dart`

Реализация HLC для total ordering операций без координации.

### Формат строки
`<physical_ms>-<counter_4hex>-<device_uuid_8chars>`

Пример: `1705312200000-0001-a1b2c3d4`

### Интерфейс

```dart
class Hlc implements Comparable<Hlc> {
  final int physicalMs;     // Wall clock в миллисекундах
  final int counter;        // Монотонный счётчик (0-65535)
  final String deviceId;    // Первые 8 символов UUID устройства

  // Создать новый HLC как следствие локального события
  static Hlc now(Hlc? last, String deviceId);

  // Создать новый HLC после получения внешней операции
  static Hlc receive(Hlc remote, Hlc? last, String deviceId);

  // Сериализация: "1705312200000-0001-a1b2c3d4"
  String toKey();
  static Hlc fromKey(String key);

  // Сравнение: сначала physicalMs, потом counter, потом deviceId
  @override int compareTo(Hlc other);
}
```

### Алгоритм `now(last, deviceId)`
```
physical = max(DateTime.now().millisecondsSinceEpoch, last?.physicalMs ?? 0)
counter  = (physical == last?.physicalMs) ? (last!.counter + 1) : 0
if counter > 65535: physical = physical + 1, counter = 0  // overflow protection
return Hlc(physical, counter, deviceId)
```

### Алгоритм `receive(remote, last, deviceId)`
```
physical = max(DateTime.now().millisecondsSinceEpoch, remote.physicalMs, last?.physicalMs ?? 0)
if physical == last?.physicalMs && physical == remote.physicalMs:
  counter = max(last!.counter, remote.counter) + 1
elif physical == last?.physicalMs:
  counter = last!.counter + 1
elif physical == remote.physicalMs:
  counter = remote.counter + 1
else:
  counter = 0
return Hlc(physical, counter, deviceId)
```

Регистрируется в GetIt как singleton. Хранит `lastHlc` и обновляет `device.lastHlc`.

---

## 4. VaultService

Файл: `lib/VaultSystem/vault_service.dart`

Основной сервис для работы с файловой системой vault.
Для MVP работает через `dart:io` (internal storage).
В этапе 6 будет заменён абстракцией `VaultFileSystem`.

### Инициализация

```dart
class VaultService {
  // Инициализировать новый vault в указанной папке.
  // Создаёт структуру .noetec/, .sync/, vault/
  // Генерирует device.json с новым UUID
  // Создаёт welcome.md с начальным содержимым
  Future<VaultInfo> initVault(String rootPath, {required String vaultName, required String deviceName});

  // Открыть существующий vault.
  // Читает .noetec/device.json и .noetec/config.json
  // Проверяет структуру (создаёт отсутствующие папки)
  Future<VaultInfo> openVault(String rootPath);

  // Получить путь к директории vault во внутреннем хранилище
  // Используется для MVP (path_provider)
  static Future<String> getDefaultVaultRootPath();
}
```

### Операции с файловым деревом

```dart
// Получить дерево файлов vault/ (без .noetec/ и .sync/)
// Кешируется в .noetec/cache/file_tree.json
Future<FolderNode> getFileTree();

// Инвалидировать кеш и перестроить дерево
Future<FolderNode> rebuildFileTree();
```

### Файловые операции

```dart
// Создать новый .md файл
// Генерирует UUID для документа
// Создаёт frontmatter
// Создаёт начальный пустой блок
// Создаёт папку в .sync/vault/ для oplog
// Возвращает relativePath (относительно vault/)
Future<String> createFile(String relativePath);

// Удалить .md файл
// Удаляет файл из vault/
// НЕ удаляет папку из .sync/vault/ (для истории)
// Создаёт file_delete запись в oplog (этап 4)
Future<void> deleteFile(String relativePath);

// Переименовать/переместить .md файл
// Создаёт file_rename запись в oplog (этап 4)
Future<void> renameFile(String oldRelativePath, String newRelativePath);

// Создать папку в vault/
Future<void> createFolder(String relativePath);

// Удалить папку (рекурсивно, только если пустая или по подтверждению)
Future<void> deleteFolder(String relativePath);

// Переименовать папку
Future<void> renameFolder(String oldRelativePath, String newRelativePath);
```

### Чтение/запись содержимого

```dart
// Прочитать .md файл
// Возвращает: {frontmatter, markdownContent (без frontmatter)}
Future<({DocumentFrontmatter frontmatter, String content})> readFile(String relativePath);

// Записать .md файл
// Вычисляет новый content_hash
// Обновляет frontmatter (modified, modified_by, content_hash)
// Записывает файл с обновлённым frontmatter + content
Future<void> writeFile(String relativePath, String content, String deviceUuid);

// Вычислить SHA-256 от строки контента (без frontmatter)
static String computeContentHash(String content);

// Проверить все файлы vault/ на внешние изменения
// Возвращает список файлов где content_hash не совпадает
Future<List<String>> detectExternalChanges();
```

---

## 5. DocumentFrontmatterCodec

Файл: `lib/VaultSystem/document_frontmatter_codec.dart`

Парсинг и генерация YAML frontmatter в .md файлах.

```dart
class DocumentFrontmatterCodec {
  // Разделить файл на frontmatter + content
  // Если frontmatter отсутствует — создать новый (с новым UUID)
  static ({DocumentFrontmatter frontmatter, String content}) parse(String fileContent);

  // Собрать файл из frontmatter + content
  static String encode(DocumentFrontmatter frontmatter, String content);
}
```

**Формат файла:**
```markdown
---
id: <uuid>
content_hash: sha256:<hex>
modified: <iso8601>
modified_by: <device-uuid>
---

<markdown content>
```

Парсер должен корректно обрабатывать:
- Файлы без frontmatter (legacy или созданные внешне)
- Frontmatter с неизвестными полями (игнорировать, сохранять при записи)
- Пустые файлы

---

## 6. Интеграция с DocumentModel

### 6.1. DocumentLoader

Файл: `lib/VaultSystem/document_loader.dart`

```dart
class DocumentLoader {
  // Загрузить .md файл в DocumentModel
  // 1. VaultService.readFile() → {frontmatter, content}
  // 2. markdownToBlocks(content) → List<TextBlock>
  // 3. Создать DocumentModel с id = frontmatter.id
  // 4. Зарегистрировать в OpenedDocumentsManager
  // 5. Сохранить relativePath в метаданных документа
  Future<DocumentModel> loadDocument(String relativePath);

  // Сохранить DocumentModel обратно в .md файл
  // 1. blocksToMarkdown(document.rootBlocks) → content
  // 2. VaultService.writeFile(relativePath, content, deviceUuid)
  Future<void> saveDocument(DocumentModel document, String relativePath);
}
```

### 6.2. Расширение DocumentModel

Добавить в `DocumentModel`:
```dart
String? vaultRelativePath;    // Путь относительно vault/ (null если не загружен из файла)
String? title;                // Имя файла без расширения (для отображения)
```

### 6.3. Расширение OpenedDocumentsManager

Добавить маппинг `relativePath → documentId` для быстрого поиска
уже открытых документов (чтобы не открывать один файл дважды).

---

## 7. DeviceSetupService

Файл: `lib/VaultSystem/device_setup_service.dart`

Сервис первого запуска и настройки устройства.

```dart
class DeviceSetupService {
  // Проверить, настроено ли устройство (есть ли .noetec/device.json)
  Future<bool> isDeviceSetup(String vaultRootPath);

  // Инициализировать устройство (при первом запуске)
  // Генерирует UUID, сохраняет device.json
  Future<DeviceIdentity> setupDevice(String vaultRootPath, {required String deviceName});

  // Прочитать identity из device.json
  Future<DeviceIdentity> loadDeviceIdentity(String vaultRootPath);

  // Сохранить обновлённый last_hlc
  Future<void> saveLastHlc(String vaultRootPath, String hlc);
}
```

---

## 8. Обновление DI (configure_di.dart)

Добавить в `configureDI()`:

```dart
// 1. Определить путь к vault (MVP: internal storage)
final vaultRootPath = await VaultService.getDefaultVaultRootPath();

// 2. Открыть или создать vault
VaultInfo vaultInfo;
if (await VaultService.vaultExists(vaultRootPath)) {
  vaultInfo = await VaultService.openVault(vaultRootPath);
} else {
  // Для MVP: создать vault с именем "My Notes" и именем устройства из Platform
  vaultInfo = await VaultService.initVault(
    vaultRootPath,
    vaultName: 'My Notes',
    deviceName: await _getDefaultDeviceName(),
  );
}

// 3. Зарегистрировать сервисы
di.registerSingleton<VaultInfo>(vaultInfo);
di.registerSingleton<VaultService>(VaultService(vaultInfo));
di.registerSingleton<HlcService>(HlcService(vaultInfo.device));
di.registerSingleton<DocumentLoader>(DocumentLoader(...));

// 4. Загрузить welcome.md вместо hardcoded документа
final welcomeDoc = await documentLoader.loadDocument('welcome.md');
```

---

## 9. Расширение MarkdownSystem

### 9.1. Frontmatter-aware парсинг

Текущий `markdownToBlocks()` получает на вход строку markdown.
Нужно убедиться что frontmatter-блок (`---...\n---\n`) уже **отрезан**
перед передачей в парсер (это делает `DocumentFrontmatterCodec.parse()`).

Существующий markdown парсер и сериализатор не трогаем.

### 9.2. Block ID для новых блоков

Текущий `FencedDirectiveSyntax` уже парсит `::: {#id}` блоки.
При создании нового файла или нового блока без ID — генерировать UUID через `IdService`.

---

## 10. Структура файлов нового кода

```
lib/
└── VaultSystem/
    ├── models/
    │   ├── device_identity.dart
    │   ├── vault_config.dart
    │   ├── vault_info.dart
    │   ├── file_tree_node.dart
    │   └── document_frontmatter.dart
    ├── hlc.dart
    ├── hlc_service.dart
    ├── vault_service.dart
    ├── document_frontmatter_codec.dart
    ├── document_loader.dart
    └── device_setup_service.dart
```

---

## 11. Тесты

| Тест | Файл |
|---|---|
| HLC: `now()` монотонность, overflow | `test/VaultSystem/hlc_test.dart` |
| HLC: `receive()` causal ordering | `test/VaultSystem/hlc_test.dart` |
| HLC: сериализация/десериализация | `test/VaultSystem/hlc_test.dart` |
| Frontmatter: парсинг полного файла | `test/VaultSystem/document_frontmatter_codec_test.dart` |
| Frontmatter: файл без frontmatter | `test/VaultSystem/document_frontmatter_codec_test.dart` |
| Frontmatter: encode→decode round-trip | `test/VaultSystem/document_frontmatter_codec_test.dart` |
| VaultService: создание vault (структура папок) | `test/VaultSystem/vault_service_test.dart` |
| VaultService: createFile/readFile/writeFile | `test/VaultSystem/vault_service_test.dart` |
| VaultService: detectExternalChanges | `test/VaultSystem/vault_service_test.dart` |
| DocumentLoader: loadDocument round-trip | `test/VaultSystem/document_loader_test.dart` |

---

## 12. Критерии готовности этапа

- [ ] `VaultService.initVault()` создаёт корректную структуру папок
- [ ] `VaultService.createFile()` создаёт .md с валидным frontmatter
- [ ] `VaultService.writeFile()` обновляет content_hash в frontmatter
- [ ] `DocumentFrontmatterCodec` корректно парсит файлы с и без frontmatter
- [ ] `DocumentLoader.loadDocument()` загружает файл в DocumentModel
- [ ] `DocumentLoader.saveDocument()` сохраняет DocumentModel в файл
- [ ] `HlcService.now()` возвращает монотонно возрастающие значения
- [ ] При запуске приложение загружает welcome.md вместо hardcoded документа
- [ ] Все существующие тесты продолжают проходить
- [ ] Новые тесты написаны и проходят
