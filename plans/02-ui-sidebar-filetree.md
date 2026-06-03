# Этап 2: UI — Sidebar и дерево файлов

## Цель

Добавить навигацию, sidebar с деревом файлов vault, multi-document workflow.
После этого этапа пользователь может создавать, удалять, переименовывать папки
и файлы, переключаться между документами.

**Зависимость:** Этап 1 завершён (VaultService, FileTreeNode, DocumentLoader).

---

## 1. AppNavigationState

Файл: `lib/AppNavigation/app_navigation_state.dart`

Заменяет hardcoded `DocumentEditorWidget` в `main.dart`.
State-based навигация без router-пакетов — через `ValueNotifier`.

```dart
sealed class AppScreen {}

// Приложение только что открыто, vault не создан
class SetupScreen extends AppScreen {}

// Vault открыт, документ не выбран
class VaultBrowseScreen extends AppScreen {
  final VaultInfo vault;
}

// Открыт конкретный документ
class DocumentScreen extends AppScreen {
  final VaultInfo vault;
  final String relativePath;      // Путь относительно vault/
  final DocumentModel document;
}

class AppNavigationState {
  final ValueNotifier<AppScreen> currentScreen;

  void navigateToSetup();
  void navigateToVault(VaultInfo vault);
  void navigateToDocument(VaultInfo vault, String relativePath, DocumentModel document);
  void closeDocument();           // Вернуться к VaultBrowseScreen
}
```

Регистрируется в GetIt как singleton.

---

## 2. Корневой виджет приложения

### 2.1. AppRoot

Файл: `lib/AppNavigation/app_root_widget.dart`

Заменяет прямое использование `DocumentEditorWidget` в `main.dart`.

```dart
class AppRootWidget extends WatchingStatefulWidget {
  @override
  Widget build(BuildContext context) {
    final screen = watch(di<AppNavigationState>().currentScreen);
    return switch (screen) {
      SetupScreen()       => SetupScreenWidget(),
      VaultBrowseScreen() => LayoutShellWidget(screen: screen, child: EmptyEditorWidget()),
      DocumentScreen()    => LayoutShellWidget(screen: screen, child: DocumentEditorWidget(...)),
    };
  }
}
```

### 2.2. LayoutShell

Файл: `lib/AppNavigation/layout_shell_widget.dart`

Определяет desktop vs mobile layout на основе ширины окна.

```dart
class LayoutShellWidget extends StatelessWidget {
  final Widget child;      // Основной контент (редактор или пустой экран)

  static const double kSidebarBreakpoint = 768.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kSidebarBreakpoint) {
          return DesktopLayoutWidget(child: child);
        } else {
          return MobileLayoutWidget(child: child);
        }
      },
    );
  }
}
```

---

## 3. Desktop Layout

Файл: `lib/AppNavigation/desktop_layout_widget.dart`

```
+------------------+---------------------------+
|   SidebarWidget  |  AppBar (title + actions) |
|                  +---------------------------+
|  [vault name]    |                           |
|  [new file btn]  |   DocumentEditorWidget    |
|  [new folder]    |   или EmptyEditorWidget   |
|                  |                           |
|  FileTreeWidget  |                           |
|                  |                           |
+------------------+---------------------------+
```

**Особенности:**
- `Row` с `SidebarWidget` + `Expanded(child: child)`
- Sidebar имеет resizable ширину: от 150 до 480px, default 240px
- Drag handle между sidebar и контентом
- Ширина сохраняется в `.noetec/config.json`
- Кнопка collapse: sidebar схлопывается до иконки (~48px) с анимацией
- При collapse показываются только иконки (файл, папка)

### SidebarWidget

Файл: `lib/Sidebar/sidebar_widget.dart`

```
+------------------+
| [≡] My Vault  [+]|   ← имя vault + кнопка new file
+------------------+
| 📁 notes     [>] |   ← папка (раскрыть/свернуть)
|   📁 daily   [>] |
|     📄 today     |   ← активный файл (подсвечен)
|     📄 yesterday |
|   📄 project.md  |
| 📄 welcome.md    |
+------------------+
```

Состояние expanded папок хранится в `ValueNotifier<Set<String>>` (set из relativePath).

---

## 4. Mobile Layout

Файл: `lib/AppNavigation/mobile_layout_widget.dart`

```dart
class MobileLayoutWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: Text(documentTitle),
        actions: [...],
      ),
      drawer: Drawer(child: SidebarWidget()),
      body: child,
    );
  }
}
```

**Поведение drawer:**
- Открывается по кнопке в AppBar или свайпом от левого края
- При выборе файла → `Navigator.pop(context)` (закрытие drawer) → открытие документа
- При нажатии "назад" на Android — закрытие drawer если открыт, иначе системное поведение

---

## 5. FileTreeWidget

Файл: `lib/Sidebar/file_tree_widget.dart`

Рекурсивный виджет для отображения дерева файлов.

### FileTreeWidget (корневой)

```dart
class FileTreeWidget extends WatchingWidget {
  @override
  Widget build(BuildContext context) {
    final tree = watch(di<VaultService>().fileTreeNotifier);  // ValueNotifier<FolderNode>
    return ListView(
      children: tree.children.map((node) => FileTreeNodeWidget(node: node)).toList(),
    );
  }
}
```

### FileTreeNodeWidget

```dart
class FileTreeNodeWidget extends StatelessWidget {
  final FileTreeNode node;

  @override
  Widget build(BuildContext context) {
    return switch (node) {
      FolderNode() => FolderNodeWidget(node: node),
      FileNode()   => FileNodeWidget(node: node),
    };
  }
}
```

### FolderNodeWidget

```dart
class FolderNodeWidget extends StatelessWidget {
  // Отображает папку с возможностью expand/collapse
  // Левый отступ = уровень вложенности * 16px
  // Иконка: стрелка вправо (свёрнут) / вниз (развёрнут) + иконка папки
  // Правый клик (desktop) / long press (mobile) → контекстное меню
  // При expand: показать children рекурсивно
}
```

### FileNodeWidget

```dart
class FileNodeWidget extends StatelessWidget {
  // Отображает файл
  // Левый отступ = уровень вложенности * 16px
  // Иконка: документ
  // Активный файл: фоновая подсветка
  // Клик → navigateToDocument()
  // Правый клик / long press → контекстное меню
}
```

### Контекстное меню

**Для файла:** Rename | Delete (+ разделитель) | New file here
**Для папки:** Rename | Delete | New file here | New folder here

Desktop: `ContextMenuRegion` или `GestureDetector` с `onSecondaryTapUp`.
Mobile: `GestureDetector` с `onLongPress` → показать `ModalBottomSheet` с действиями.

---

## 6. Sidebar Header

Файл: `lib/Sidebar/sidebar_header_widget.dart`

```
+--------------------------------+
| 📚 My Vault              [−]  |
|                [📄+] [📁+]    |
+--------------------------------+
```

- Имя vault из `VaultInfo.config.name`
- Кнопка `[−]` — collapse sidebar (только desktop)
- Кнопки `[📄+]` и `[📁+]` — создать файл / создать папку в корне vault
- При collapse: показывается только `[≡]` для expand обратно

---

## 7. SetupScreen

Файл: `lib/AppNavigation/setup_screen_widget.dart`

Показывается при первом запуске (нет vault) или при ошибке открытия vault.

**MVP версия:**

```
+----------------------------------+
|         Noetec                   |
|                                  |
|  Welcome to Noetec!              |
|                                  |
|  Vault name:  [____________]     |
|  Device name: [____________]     |
|                                  |
|        [Create Vault]            |
+----------------------------------+
```

- Vault name: default "My Notes"
- Device name: автоматически определяется (`Platform.operatingSystem` + random suffix)
- `[Create Vault]` → `VaultService.initVault()` → `navigateToVault()`

Позже (этап 6): добавить кнопку "Open existing vault" для file_picker.

---

## 8. EmptyEditorWidget

Файл: `lib/DocumentView/empty_editor_widget.dart`

Показывается когда vault открыт, но документ не выбран.

```
+--------------------------------------+
|                                      |
|        Select a document             |
|        from the sidebar              |
|                                      |
|   [New Document]                     |
+--------------------------------------+
```

---

## 9. Диалоги

Все диалоги реализуются через `showDialog()` с `AlertDialog`.

### 9.1. CreateFileDialog

Файл: `lib/Sidebar/dialogs/create_file_dialog.dart`

```
Create new document
─────────────────────
Name: [____________]
      (автоматически добавляем .md если нет)

[Cancel]  [Create]
```

Валидация:
- Не пустое
- Не содержит `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`
- Нет файла с таким именем в указанной папке
- Показывать ошибку inline под полем

### 9.2. CreateFolderDialog

Аналогично CreateFileDialog, но для папки.

### 9.3. RenameDialog

```
Rename
─────────────
New name: [notes      ]

[Cancel]  [Rename]
```

Предзаполнен текущим именем, весь текст выделен при открытии.
Те же правила валидации.

### 9.4. DeleteConfirmDialog

```
Delete "daily"?
──────────────────────────────
This will permanently delete the
folder and all its contents (3 files).

[Cancel]  [Delete]
```

Кнопка Delete — красная/деструктивная.

---

## 10. AppBar для DocumentScreen

Файл: `lib/DocumentView/document_app_bar_widget.dart`

```
+----------------------------------------------+
| [≡]  daily / today.md          [⋯]   [🔍]   |
+----------------------------------------------+
```

- Breadcrumb путь (кликабельный на каждый сегмент → навигация в папку)
- `[⋯]` кнопка → dropdown: Rename, Delete, Show in Finder/Explorer
- `[🔍]` поиск (placeholder, этап будущего)
- Индикатор состояния сохранения (правый угол): "Saving..." | "✓ Saved" | "● Unsaved" (этап 3)

---

## 11. Реактивность дерева файлов

`VaultService` должен предоставить `ValueNotifier<FolderNode> fileTreeNotifier`.

При операциях `createFile`, `deleteFile`, `renameFile`, `createFolder`, `deleteFolder`, `renameFolder`:
1. Выполнить операцию на диске
2. Инвалидировать кеш
3. Обновить `fileTreeNotifier.value` → UI автоматически перестроится

Для эффективности: при изменении одного файла — не перестраивать всё дерево,
а обновить только изменённую ветку.

---

## 12. Структура новых файлов

```
lib/
├── AppNavigation/
│   ├── app_navigation_state.dart
│   ├── app_root_widget.dart
│   ├── layout_shell_widget.dart
│   ├── desktop_layout_widget.dart
│   ├── mobile_layout_widget.dart
│   └── setup_screen_widget.dart
├── Sidebar/
│   ├── sidebar_widget.dart
│   ├── sidebar_header_widget.dart
│   ├── file_tree_widget.dart
│   ├── file_tree_node_widget.dart
│   ├── folder_node_widget.dart
│   ├── file_node_widget.dart
│   └── dialogs/
│       ├── create_file_dialog.dart
│       ├── create_folder_dialog.dart
│       ├── rename_dialog.dart
│       └── delete_confirm_dialog.dart
└── DocumentView/
    ├── empty_editor_widget.dart
    └── document_app_bar_widget.dart   (новый, вынести из main.dart)
```

Изменения в существующих файлах:
- `lib/main.dart` — заменить `DocumentEditorWidget` на `AppRootWidget`
- `lib/configure_di.dart` — добавить `AppNavigationState` в DI
- `lib/DocumentView/document_editor_widget.dart` — принимать `DocumentModel` как параметр

---

## 13. Тесты

| Тест | Файл |
|---|---|
| AppNavigationState: переходы между экранами | `test/AppNavigation/app_navigation_state_test.dart` |
| FileTreeWidget: корректная отрисовка дерева | `test/Sidebar/file_tree_widget_test.dart` |
| FileTreeWidget: expand/collapse папок | `test/Sidebar/file_tree_widget_test.dart` |
| Диалог: валидация имени файла (спец. символы) | `test/Sidebar/dialogs/create_file_dialog_test.dart` |
| LayoutShell: desktop vs mobile breakpoint | `test/AppNavigation/layout_shell_test.dart` |

---

## 14. Критерии готовности этапа

- [ ] Desktop: sidebar с деревом файлов, resizable, collapsible
- [ ] Mobile: drawer с тем же деревом
- [ ] Файл в дереве кликается → открывается в редакторе
- [ ] Контекстное меню на файлах и папках работает
- [ ] Диалоги создания/удаления/переименования работают с валидацией
- [ ] Активный документ подсвечен в дереве
- [ ] SetupScreen показывается при первом запуске
- [ ] При выборе файла на mobile drawer закрывается
- [ ] Дерево обновляется после операций без перезапуска
- [ ] Существующие тесты проходят
