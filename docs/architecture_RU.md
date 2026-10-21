# Архитектура Noetec

[English](architecture.md) · [**Русский**](architecture_RU.md)

Карта кодовой базы верхнего уровня. Она говорит, *где* живёт каждая тема, чтобы можно было
сразу перейти к нужным файлам; это не глубокое погружение. Причины каждого
решения живут в ADR в `docs/decisions/`, а нормативное поведение — в
спецификациях в `docs/specs/` — они и есть контракт, эта карта лишь указывает
на него.

Noetec — **локально-первичный (local-first) блочный редактор заметок** на Flutter/Dart. Заметки —
это обычные Markdown-файлы с YAML-frontmatter в хранилище (vault) на диске; редактор
работает с типизированным деревом блоков в памяти и сериализует его обратно в Markdown.

## Как читать эту карту

- Данные текут в **одном направлении** (вдохновлено Flux, ADR-0001): View → команда →
  обработчик → нотифаер → View.
- Зависимости связываются в **одном месте**: `lib/app/configure_di.dart` (get_it,
  ADR-0005). Если классу нужен другой, он принимает его аргументом конструктора —
  никогда через глобальный поиск.
- Верхнеуровневая единица организации — **система** в `lib/systems/`. Каждая
  система владеет своим срезом доменного поведения и своим реактивным состоянием.

## Структура каталогов

```
lib/
├── main.dart                 Точка входа: configureDI() → VaultSystem.init() → runApp
├── app/                      Композиция приложения: DI, корневой виджет, оболочка, роутер
│   ├── configure_di.dart     Все регистрации get_it (единственная точка связывания)
│   ├── main_app_widget.dart  Корневой виджет (MaterialApp.router + сохранение по жизненному циклу)
│   ├── app_shell.dart        Оболочка раскладки для десктопа и мобильных
│   └── router.dart           go_router: /welcome ↔ /editor (редиректы по состоянию хранилища)
├── entity/                   Чистые доменные данные (без Flutter UI, без сервисов)
│   ├── vault.dart            VaultEntity
│   ├── hlc.dart              Hlc — гибридные логические часы для причинного упорядочивания
│   ├── page/                 Page, блоки, текстовые сегменты, выделение, действия редактирования
│   ├── device/               DeviceIdentity
│   └── user/                 UserIdentity
├── service/                  Инфраструктурные и смежные с доменом сервисы (интерфейсы)
├── systems/                  Системы функциональности (основное — см. «Системы» ниже)
├── view/                     Виджеты. Тонкие; наблюдают нотифаеры, никогда не мутируют состояние
└── (generated *.g.dart)      вывод build_runner — вручную не правится
```

## Цикл Flux (ADR-0001)

Состояние движется только в одном направлении; циклических зависимостей между системами нет.

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

1. **View** — это `WatchingWidget` (например, `lib/view/widgets/editor_area.dart`,
   `lib/view/screens/welcome_screen/welcome_screen.dart`). Виджеты остаются тонкими:
   они рендерят и реагируют, бизнес-логики в них нет.
2. **Команда** — объект `Command`, которым владеет система (из `command_it`),
   например `VaultSystem.createVaultCommand` / `openVaultCommand` /
   `closeVaultCommand` в `lib/systems/vault/vault_system.dart`. Виджет вызывает
   `command.run(param)`; команды предоставляют `.isRunning`, `.errors`, `.value`.
3. **Обработчик** — приватный метод, стоящий за командой (например, `_createVault`,
   `_openVault`). Он выполняет доменную работу и мутирует состояние системы.
4. **Нотифаеры** — реактивное состояние, которым владеет непосредственно система (из
   `listen_it`, реэкспортируется `command_it`): `CustomValueNotifier`,
   `ListNotifier`, обычный `ValueNotifier`. Слоя ViewModel нет; системы
   хранят состояние, а виджеты наблюдают за ним напрямую (ADR-0005).
5. **WatchingWidget** — подписывается через `watchValue<System, T>((s) => s.field)`
   и перестраивается, когда наблюдаемый нотифаер меняется. Цикл повторяется.

**Редактор — вариант того же цикла.** Сырые нажатия клавиш приходят через
обработчики `UserInputService` → `PageEditingSubsystem` мутирует дерево блоков `PageEntity`
→ подсистема испускает `PageEditAction` в `PageActionDispatcher` →
`PersistenceSystem` слушает и помечает страницу как dirty. Шаг диспетчеризации действий —
это эквивалент «команды» в редакторе: он отделяет множество микро-правок редактора
(вставка, удаление, разделение, слияние) от задачи персистентности.

## DI-контейнер (ADR-0005)

`lib/app/configure_di.dart` — **единственное** место, где связываются зависимости.
`configureDI()` регистрирует синглтоны в `GetIt.instance` в порядке зависимостей
(сначала сервисы, затем системы, которые от них зависят). Тестовый код подставляет фейки через
необязательные параметры `fileSystem`, `settings` и `secureKeyStore`, поэтому
остальной граф остаётся настоящим.

Соглашения:
- Сервисы определяются как `abstract interface class IXxxService` с
  `XxxServiceImpl` в том же файле (`lib/service/`).
- Системы — конкретные классы (не за интерфейсами) и принимают свои
  зависимости параметрами конструктора.

Стек — `get_it` (DI) + `watch_it` (реактивные представления) + `listen_it`
(реактивное состояние) + `command_it` (команды) — одна цельная экосистема, согласно
ADR-0005.

## Системы

### Хранилище (Vault) — `lib/systems/vault/`

Корень домена. `VaultSystem` владеет текущим хранилищем
(`currentVault: CustomValueNotifier<VaultEntity?>`), списком недавних хранилищ
(`recentVaults: ListNotifier<VaultEntity>`) и тремя командами хранилища
(create/open/close). Он читает и пишет манифест хранилища (`.noetec/vault.json`),
создаёт скелет каталогов хранилища и испускает потоки `ClosingEvent` / `vaultCreated`,
на которые подписываются другие системы. `VaultRepositoryImpl` (`IVaultRepository`)
сохраняет список недавних хранилищ через `ISettingsService`.

Смежное (в `lib/service/`): `VaultFileService` (список/создание/переименование/удаление файлов
страниц), `RenameController` (многофазное переименование), `PageFileNameSanitizer`.

### Страница (Page) — `lib/systems/page_system/`

Модель документа в памяти. `PageSystem` хранит открытые страницы
(`openPages: Map<String, PageEntity>`), активную страницу (`activePageId`) и счётчик
`openPagesVersion`, за которым редактор следит для перестроек. Он загружает страницы из
Markdown (через `MarkdownSystem` + `PageFrontmatterCodec`) и сохраняет их обратно,
а также сохраняет сессию (`.noetec/session.json`).

От него зависят три подсистемы, создаваемые в его конструкторе:
- `editing` (`PageEditingSubsystem`) — применяет текстовые правки к дереву блоков и
  испускает `PageEditAction`.
- `selection` (`PageSelectionSubsystem`) — состояние курсора и выделения диапазона.
- `clipboard` (`PageClipboardSubsystem`) — копирование/вырезание/вставка в блочном виде.

`PageActionDispatcher` раздаёт каждый `PageEditAction` слушателям (прежде всего
`PersistenceSystem`). См. также сущности `PageEntity`, `BlockEntity`,
`TextBlockEntity`, `SelectionEntity`, `PageEditAction` в `lib/entity/page/`.

### OpLog — `lib/systems/oplog_system/`

Журнал операций только на добавление, который фиксирует каждую правку и сохранение по странице, давая синхронизации
воспроизводимую и проверяемую историю. `OpLogSystem` управляет конвейером:
- `oplog_models.dart` — операции `BlockOp`/`FileOp` и `OpLogEntry`.
- `oplog_dag.dart` — `OpLogDag` отслеживает топологию причинного графа.
- `block_diff_engine.dart` / `state_reconstruction_engine.dart` — дифф и
  восстановление состояния блоков по записям.
- `oplog_writer.dart` / `oplog_reader.dart` / `oplog_serializer.dart` — персистентность.
- `oplog_signer.dart` / `oplog_verifier.dart` — подпись и проверка записей Ed25519
  (ADR-0006), с использованием `ICryptoService` + `ISecureKeyStore`.

Метки времени используют `HlcService` (гибридные логические часы) для причинно-согласованного
упорядочивания без доверия к системным часам. См. `docs/specs/sync-security_RU.md`.

### Персистентность (Persistence) — `lib/systems/persistence_system/`

Превращает правки в долговечные файлы. `PersistenceSystem` слушает
`PageActionDispatcher`, буферизует правки в журнале упреждающей записи (`WalService`) и
отслеживает состояние сохранения по странице (нотифаеры `clean`/`dirty`/`saving`/`error`, которые
потребляет панель вкладок редактора). Поток сохранения: добавить в WAL → сбросить на диск → `PageSystem.savePage`
(записать Markdown) → `OpLogSystem.recordSave` → очистить WAL. `CrashRecoveryService`
+ `WalActionSerializer` воспроизводят незафиксированные действия после сбоя, чтобы ни одна правка не
потерялась.

### Синхронизация (Sync) — `lib/systems/sync_system/`

Согласует локальный OpLog с изменениями с других устройств и из файлов (`.sync/`).
`SyncSystem` наблюдает за хранилищем и запускает слияние:
- `SyncWatcher` — наблюдает за входящими изменениями синхронизации.
- `VaultWatcher` — наблюдает за внешними правками файлов хранилища.
- `MergeEngine` / `MergeApplier` — вычисляют и применяют слияния.
- `ConflictResolver` / `ConflictStore` — обнаруживают, сохраняют и разрешают конфликты.
- `ExternalEditHandler` — вливает правки, сделанные извне, обратно в OpLog.

Состояние видно как `SyncStatus` и `DocumentSyncState` по документу. Глубокие правила
живут в `docs/specs/sync-security_RU.md` и ADR-0006/0007.

### Markdown — `lib/systems/markdown_system/`

Граница между деревом блоков и форматом Markdown-файла.
`MarkdownSystem` предоставляет `parseMarkdown` (текст → список `TextBlockEntity`) и
`serializeBlocks` (блоки → текст), построенные на пакете `markdown`. Собственный
`FencedDirectiveSyntax` (`markdown_parser.dart`) обрабатывает ограждённые
директивы `::: {#id}`, несущие идентификаторы блоков (ADR-0002). Канонический формат файла —
`docs/specs/file-format_RU.md`.

### Пользовательский ввод (User Input) — `lib/systems/user_input_system/`

Превращает события ввода платформы в правки документа и изменения выделения.
`UserInputService` маршрутизирует их четырём обработчикам (в `handlers/`):
- `ImeInputHandler` — текстовые дельты от IME (сырую текстовую поверхность даёт
  `UserRawTextInputWidget` со своим `DeltaTextInputClient`).
- `KeyboardInputHandler` — события клавиш, состояние модификаторов, сокращения.
- `PointerInputHandler` — клики, перетаскивания, привязка выделения.
- `ClipboardInputHandler` — копировать/вырезать/вставить/выделить всё.

Все четыре в итоге управляют `PageEditingSubsystem` (и подсистемами выделения и буфера обмена)
в `PageSystem`.

## Сущности — `lib/entity/`

Чистые данные, без Flutter UI и без зависимостей от сервисов:

| Сущность | Файл | Назначение |
|---|---|---|
| `VaultEntity` | `vault.dart` | идентификатор хранилища, имя, корневой путь, время создания |
| `Hlc` | `hlc.dart` | гибридные логические часы (`physicalMs`, `counter`, `deviceId`) |
| `PageEntity` | `page/page.dart` | идентификатор страницы, путь, дерево блоков, выделение |
| `BlockEntity` / `TextBlockEntity` | `page/block/` | типизированное дерево блоков (`id`, `parentId`, `children`, `segments`) |
| `TextSegment` (+ `FormattedSegment`, `LinkSegment`) | `page/block/text/` | стилизованные текстовые фрагменты внутри блока |
| `SelectionEntity` (+ `NoSelection`, `SingleCursor`, `Range`) | `page/selection.dart` | состояние курсора и диапазона |
| `PageEditAction` (sealed) | `page/page_edit_action.dart` | операции редактирования, которые испускает редактор |
| `DeviceIdentity` | `device/` | ключ и идентификатор устройства (ADR-0007) |
| `UserIdentity` | `user/` | идентичность пользователя (ADR-0007) |

## Сервисы — `lib/service/`

Пары «интерфейс + реализация», от которых системы зависят через DI:

| Интерфейс | Реализация | Назначение |
|---|---|---|
| `IFileSystemService` | `FileSystemServiceImpl` | весь файловый ввод-вывод (абстракция платформы) |
| `ISettingsService` | `SettingsServiceImpl` | настройки приложения ключ-значение |
| `ISecureKeyStore` | `SecureKeyStoreImpl` | защищённое хранение ключей |
| `ICryptoService` | `CryptoServiceImpl` | примитивы подписи и хеширования |
| `IIdService` | `IdService` | генерация идентификаторов |
| `IDeviceService` | `DeviceServiceImpl` | идентичность устройства и атрибуция |
| `IUserService` | `UserServiceImpl` | идентичность пользователя |
| `ITrustStore` | `TrustStoreImpl` | решения о доверии (TOFU, закреплённые ключи) |

Также: `HlcService` (генерация HLC), `VaultFileService`, `RenameController`,
`PageFileNameSanitizer`.

## Представление — `lib/view/`

Тонкие виджеты. Они читают системы через `di<X>()` и подписываются через `watchValue`;
вызывают команды и обработчики, но никогда не мутируют сущности напрямую.

- `lib/app/` — `main_app_widget.dart` (корневой), `app_shell.dart` (оболочка с боковой
  панелью на десктопе против нижней навигации на мобильных), `router.dart` (go_router, редиректы между
  `/welcome` и `/editor` по `currentVault`).
- `screens/` — `welcome`, `editor`, `settings`, `main_app_loading`.
- `widgets/` — `icon_rail`, `content_panel` (+ `pages`/`settings`/`bookmarks`/
  `journal`), `editor_area` и `editor/` (`PageEditorWidget`,
  `BlockEditorWidget`, `TextBlockRenderWidget`).

## Указатели на решения и спецификации

ADR (`docs/decisions/`, неизменяемые — заменяйте, никогда не редактируйте):

- **0001** Однонаправленный поток данных во Flux — цикл выше.
- **0002** Идентификаторы блоков через ограждённые директивы (`::: {#id}`) в Markdown.
- **0003** Идентичности устройства нет, пока не реализована синхронизация.
- **0004** Локально-первичное файловое хранилище как Markdown + YAML-frontmatter.
- **0005** DI на get_it с экосистемой watch_it / listen_it / command_it.
- **0006** Подписи Ed25519 для безопасности OpLog при синхронизации.
- **0007** Модель идентичности нескольких пользователей и реестров синхронизации.

Спецификации (`docs/specs/`, нормативные — RFC 2119):

- `file-format_RU.md` — формат файла страницы (frontmatter, идентификаторы блоков, хеширование).
- `sync-security_RU.md` — формат безопасности синхронизации и правила проверки.
- `01-vault-user-workflow.spec` — сквозной пользовательский сценарий работы с хранилищем.

Направление продукта: `docs/product/vision_RU.md`; дорожная карта: `ROADMAP_RU.md`.
