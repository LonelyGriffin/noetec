# Этап 6: External Vault и Multi-Vault

## Цель

Дать пользователю возможность выбирать произвольную папку для vault
(не только внутреннее хранилище приложения). Поддержать несколько vault'ов.
Реализовать платформенные абстракции для работы с файловой системой.

**После этого этапа:** приложение production-ready на всех платформах.
Пользователь может синхронизировать vault через Dropbox или iCloud Drive,
выбрав их как папку vault.

**Зависимость:** Этапы 1-5 завершены.

---

## 1. Новые зависимости

```yaml
dependencies:
  file_picker: ^8.1.2          # Выбор папки (нативный диалог)
  saf: ^1.0.0                  # Android Storage Access Framework
  secure_bookmark: ^1.0.0      # iOS/macOS security-scoped bookmarks
  flutter_secure_storage: ^9.0.0  # Keychain для хранения закладок
  shared_preferences: ^2.3.2   # Хранение пути vault (desktop)
```

---

## 2. Абстрактный интерфейс VaultFileSystem

Файл: `lib/VaultSystem/vault_file_system.dart`

Заменяет прямые вызовы `dart:io` в `VaultService`.
Позволяет иметь разные реализации для разных платформ.

```dart
abstract class VaultFileSystem {
  // Чтение файла
  Future<String> readFile(String absolutePath);

  // Запись файла (создаёт если не существует)
  Future<void> writeFile(String absolutePath, String content);

  // Удаление файла
  Future<void> deleteFile(String absolutePath);

  // Проверить существование файла/папки
  Future<bool> exists(String absolutePath);

  // Создать папку (рекурсивно)
  Future<void> createDirectory(String absolutePath);

  // Удалить папку (рекурсивно)
  Future<void> deleteDirectory(String absolutePath);

  // Переименовать файл или папку
  Future<void> rename(String oldPath, String newPath);

  // Получить список файлов/папок в директории
  Future<List<VaultFsEntry>> listDirectory(String absolutePath);

  // Получить lastModified
  Future<DateTime?> lastModified(String absolutePath);

  // Stream изменений в директории (если платформа поддерживает)
  // Возвращает null если не поддерживается (используется polling)
  Stream<VaultFsChangeEvent>? watchDirectory(String absolutePath);
}

class VaultFsEntry {
  final String name;
  final String absolutePath;
  final bool isDirectory;
  final DateTime? lastModified;
}

class VaultFsChangeEvent {
  final String path;
  final VaultFsChangeType type; // created, modified, deleted, renamed
}
```

---

## 3. Реализации VaultFileSystem

### 3.1. DartIoVaultFileSystem

Файл: `lib/VaultSystem/implementations/dart_io_vault_file_system.dart`

Для: Windows, Linux, macOS (без App Store sandbox), iOS (после разрешения bookmark).

```dart
class DartIoVaultFileSystem implements VaultFileSystem {
  // Прямые вызовы dart:io
  // File, Directory, FileSystemEntity

  @override
  Stream<VaultFsChangeEvent>? watchDirectory(String absolutePath) {
    // Использовать Directory.watch() или пакет watcher
    // Доступно на всех платформах где dart:io работает
    return DirectoryWatcher(absolutePath).events.map(_toVaultFsChangeEvent);
  }
}
```

### 3.2. SafVaultFileSystem

Файл: `lib/VaultSystem/implementations/saf_vault_file_system.dart`

Для: Android (когда vault вне app-specific storage).

```dart
class SafVaultFileSystem implements VaultFileSystem {
  final String treeUri;    // content:// URI дерева от SAF

  // Использует пакет saf для операций
  // saf.readFile(), saf.writeFile(), saf.listFiles() и т.д.

  @override
  Stream<VaultFsChangeEvent>? watchDirectory(String absolutePath) {
    // SAF не поддерживает нативный watch
    // Возвращаем null → будет использован polling
    return null;
  }
}
```

### 3.3. BookmarkedVaultFileSystem

Файл: `lib/VaultSystem/implementations/bookmarked_vault_file_system.dart`

Для: iOS и macOS App Store (security-scoped bookmarks).

```dart
class BookmarkedVaultFileSystem implements VaultFileSystem {
  // Оборачивает DartIoVaultFileSystem
  // Перед каждой операцией: startAccessingSecurityScopedResource()
  // После: stopAccessingSecurityScopedResource()
  final DartIoVaultFileSystem _inner;
  final String _bookmarkKey;  // Ключ в Keychain для хранения bookmark

  static Future<BookmarkedVaultFileSystem> fromBookmark(String bookmarkKey);
  static Future<BookmarkedVaultFileSystem> fromPath(String absolutePath, String bookmarkKey);
}
```

### 3.4. Фабрика

Файл: `lib/VaultSystem/vault_file_system_factory.dart`

```dart
class VaultFileSystemFactory {
  static Future<VaultFileSystem> create(String vaultRootPath) {
    if (Platform.isAndroid && _isContentUri(vaultRootPath)) {
      return SafVaultFileSystem(treeUri: vaultRootPath);
    }
    if (Platform.isIOS || (Platform.isMacOS && _isSandboxed())) {
      return BookmarkedVaultFileSystem.fromPath(vaultRootPath, 'vault_bookmark');
    }
    return DartIoVaultFileSystem(rootPath: vaultRootPath);
  }
}
```

---

## 4. Persistent Access между перезапусками

Файл: `lib/VaultSystem/vault_access_persistence.dart`

После выбора папки нужно сохранить доступ к ней, чтобы при следующем
запуске не просить пользователя выбирать снова.

```dart
class VaultAccessPersistence {
  // Сохранить доступ к vault
  Future<void> saveVaultAccess(String vaultRootPath);

  // Восстановить доступ при запуске
  Future<String?> restoreVaultAccess();

  // Проверить что доступ ещё действителен
  Future<bool> isAccessValid(String vaultRootPath);
}
```

### По платформам:

**Android (SAF):**
```dart
// content:// URI дерева сохраняется в SharedPreferences
// URI постоянный после вызова takePersistableUriPermission()
await ContentResolver.takePersistableUriPermission(
  uri,
  Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
);
await prefs.setString('vault_uri', uri);
```

**iOS / macOS App Store:**
```dart
// Создать security-scoped bookmark
final bookmark = await SecureBookmark().bookmark(path);
// Сохранить в Keychain
await FlutterSecureStorage().write(key: 'vault_bookmark', value: base64.encode(bookmark));

// При восстановлении:
final bookmarkData = await FlutterSecureStorage().read(key: 'vault_bookmark');
final path = await SecureBookmark().resolveBookmark(base64.decode(bookmarkData));
```

**Windows / Linux / macOS (без sandbox):**
```dart
// Просто сохранить абсолютный путь
await SharedPreferences.getInstance().then((prefs) =>
  prefs.setString('vault_path', absolutePath));
```

---

## 5. VaultRegistry — несколько vault'ов

Файл: `lib/VaultSystem/vault_registry.dart`

Хранится **вне** vault, в application support directory.
Путь: `<app_support>/vault_registry.json`

```dart
class VaultRegistry {
  final ValueNotifier<List<VaultEntry>> vaults;

  // Добавить vault в реестр
  Future<void> addVault(VaultEntry entry);

  // Удалить vault из реестра (не удаляет файлы!)
  Future<void> removeVault(String vaultRootPath);

  // Обновить lastOpened
  Future<void> touchVault(String vaultRootPath);

  // Загрузить/сохранить из файла
  Future<void> load();
  Future<void> save();
}

class VaultEntry {
  final String rootPath;       // Абсолютный путь (или content:// на Android)
  final String name;           // Отображаемое имя (из config.json)
  final DateTime lastOpened;
  final String? iconEmoji;     // (будущее) Кастомная иконка vault
}
```

### vault_registry.json

```json
{
  "vaults": [
    {
      "root_path": "/Users/user/Documents/MyNotes",
      "name": "My Notes",
      "last_opened": "2024-01-15T10:30:00.000Z"
    },
    {
      "root_path": "/Users/user/Dropbox/WorkNotes",
      "name": "Work Notes",
      "last_opened": "2024-01-14T15:00:00.000Z"
    }
  ]
}
```

---

## 6. Vault Picker UI

### 6.1. VaultPickerScreen

Файл: `lib/AppNavigation/vault_picker_screen.dart`

Показывается при первом запуске (нет vault'ов) или по запросу.

```
+------------------------------------------+
|  Noetec                                  |
+------------------------------------------+
|  Recent vaults:                          |
|                                          |
|  📚 My Notes              [Open]         |
|     /Users/user/Documents/MyNotes        |
|     Last opened: Today, 10:30            |
|                                          |
|  📚 Work Notes            [Open]         |
|     /Users/user/Dropbox/WorkNotes        |
|     Last opened: Yesterday, 15:00        |
|                                          |
|  ──────────────────────────────────      |
|                                          |
|  [+ Create New Vault]                    |
|  [📁 Open Existing Folder]               |
+------------------------------------------+
```

### 6.2. Создание нового vault

```
Create New Vault
──────────────────────────────
Vault name:   [My Notes      ]
Device name:  [My MacBook    ]

Location:
○ App Storage (default, private)
● Choose folder...  [Browse...]
  Selected: /Users/user/Dropbox/

        [Cancel]  [Create]
```

### 6.3. Открытие существующего vault

При выборе "Open Existing Folder":
1. `FilePicker.platform.getDirectoryPath()` → путь
2. Проверить является ли папка vault (наличие `.noetec/config.json`)
3. Если нет → предложить инициализировать как новый vault
4. Открыть vault

---

## 7. Vault Switcher

Файл: `lib/AppNavigation/vault_switcher_widget.dart`

В sidebar header: кликабельное имя vault открывает picker.

```
| 📚 My Notes ▾  [−] |
        ↓ клик
+---------------------+
| ✓ My Notes          |
|   Work Notes        |
|   ───────────────   |
|   + New Vault       |
|   📁 Open Folder    |
+---------------------+
```

Горячая клавиша: `Ctrl+Shift+O` — открыть vault switcher.

---

## 8. Рефакторинг VaultService

`VaultService` сейчас использует `dart:io` напрямую.
В этом этапе: внедрить `VaultFileSystem` как зависимость.

```dart
class VaultService {
  final VaultFileSystem _fs;  // Внедряется через конструктор

  VaultService(this._fs, ...);

  // Все методы используют _fs вместо dart:io напрямую
}
```

Это делает `VaultService` тестируемым (можно подставить mock файловую систему)
и платформо-независимым.

---

## 9. Обновление SetupScreen → VaultPickerScreen

`SetupScreen` из этапа 2 (только создание vault во внутреннем хранилище)
заменяется на полноценный `VaultPickerScreen` из этого этапа.

`AppNavigationState` обновляется:

```dart
class SetupScreen extends AppScreen {}
// Заменяется на:
class VaultPickerScreen extends AppScreen {
  final List<VaultEntry> recentVaults;
}
```

---

## 10. Обработка ошибок доступа

При открытии vault возможны ошибки:
- Папка удалена или перемещена
- Bookmark протух (iOS/macOS)
- Нет прав доступа (Android)

```dart
// В VaultService.openVault():
try {
  await _fs.exists(rootPath);
} on VaultAccessException catch (e) {
  // Показать диалог с объяснением
  // Android: "Please select the vault folder again"
  // iOS: "Please grant access to the vault folder"
  throw VaultNotAccessibleException(rootPath, e);
}
```

---

## 11. Структура новых файлов

```
lib/
├── VaultSystem/
│   ├── vault_file_system.dart                    # Абстрактный интерфейс
│   ├── vault_file_system_factory.dart
│   ├── vault_access_persistence.dart
│   ├── vault_registry.dart
│   └── implementations/
│       ├── dart_io_vault_file_system.dart
│       ├── saf_vault_file_system.dart
│       └── bookmarked_vault_file_system.dart
└── AppNavigation/
    ├── vault_picker_screen.dart
    └── vault_switcher_widget.dart
```

Изменения в существующих файлах:
- `lib/VaultSystem/vault_service.dart` — использовать `VaultFileSystem` вместо `dart:io`
- `lib/AppNavigation/app_navigation_state.dart` — `SetupScreen` → `VaultPickerScreen`
- `lib/AppNavigation/app_root_widget.dart` — показывать VaultPickerScreen
- `lib/Sidebar/sidebar_header_widget.dart` — добавить vault switcher
- `lib/configure_di.dart` — VaultRegistry, VaultFileSystemFactory, обновить SetupFlow
- `android/app/src/main/AndroidManifest.xml` — разрешения для SAF
- `ios/Runner/Info.plist` — NSDocumentsFolderUsageDescription

---

## 12. Тесты

| Тест | Файл |
|---|---|
| DartIoVaultFileSystem: CRUD операции | `test/VaultSystem/dart_io_vault_file_system_test.dart` |
| VaultFileSystem: mock реализация для тестов других сервисов | `test/helpers/mock_vault_file_system.dart` |
| VaultRegistry: добавление/удаление/load/save | `test/VaultSystem/vault_registry_test.dart` |
| VaultService: использует VaultFileSystem (через mock) | `test/VaultSystem/vault_service_test.dart` (обновлённый) |

---

## 13. Критерии готовности этапа

- [ ] Пользователь может выбрать произвольную папку для vault через нативный диалог
- [ ] На Android: SAF URI сохраняется, доступ восстанавливается при перезапуске
- [ ] На iOS/macOS: bookmark создаётся, хранится в Keychain, восстанавливается
- [ ] На Desktop: путь сохраняется в SharedPreferences
- [ ] VaultRegistry отображает список vault'ов
- [ ] Vault switcher в sidebar позволяет переключаться между vault'ами
- [ ] VaultService полностью работает через абстрактный VaultFileSystem
- [ ] VaultService тестируется с mock VaultFileSystem без реального диска
- [ ] Все существующие тесты проходят
