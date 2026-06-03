# Noetec — Vault & Sync: Обзор архитектуры и принятых решений

## Текущее состояние проекта

Noetec — Flutter (SDK ^3.10.7) блочный rich-text редактор.

**Что есть:**
- State management: GetIt + watch_it + listen_it (ValueNotifier / ListNotifier / MapNotifier)
- Модель документа: `DocumentModel` с `TextBlock`-ами и `TextSegment`-ами
- 14 user actions: InsertText, DeleteTextBack, SplitTextBlock, MoveCursor, Paste и др.
- Markdown парсер/сериализатор с fenced directives (`:::` блоки с block ID)
- Кастомный RenderBox для рендеринга текста с курсором и selection

**Чего нет:**
- Routing / навигация (один экран, один захардкоженный документ)
- Persistence / файловая система
- Vault / workspace концепция
- Multi-document UI (tabs, sidebar)
- Undo/redo

---

## Принятые архитектурные решения

| Аспект | Решение | Обоснование |
|---|---|---|
| Гранулярность операций | Block-level ops | Баланс между точностью merge и сложностью реализации. Блоки уже имеют ID (fenced directives). |
| Формат oplog | JSON Lines (.jsonl), append-only | Стандартный формат event logs. Читаем/пишем построчно, совместим с text diff tools. |
| Содержимое oplog | Diff-операции (не snapshots) | Компактно. Snapshot в корне vault — актуальное состояние. |
| Ordering событий | HLC (Hybrid Logical Clock) | Total ordering без координации. Causal ordering. Человекочитаемое время. |
| Идентификация устройств | UUID (для файлов) + имя (для отображения) | UUID гарантирует уникальность. Имя удобно для пользователя. |
| Crash recovery | WAL (Write-Ahead Log) | Минимальная потеря данных. Стандартный подход (как SQLite WAL). |
| Сохранение | Debounced autosave (3s) + ручное Ctrl+S | Комфортно для пользователя. |
| File watching | Polling (MVP) → нативный watcher позже | Простая реализация. Polling как fallback на всех платформах. |
| Навигация | State-based (ValueNotifier) | Консистентно с текущим state management. Без внешних зависимостей. |
| Хранилище MVP | Внутреннее хранилище приложения | Нет платформенных сложностей (SAF, sandbox). Быстрый старт. |
| Хранилище позже | Выбор папки (file_picker + абстракции) | Этап 6. |

---

## Структура vault на диске

```
<vault-root>/
│
├── .noetec/                          # Локальное (НЕ синхронизируется)
│   ├── device.json                   # Идентификация устройства + последний HLC
│   ├── config.json                   # Локальные настройки vault
│   ├── session.json                  # Последняя сессия (открытые документы, активный)
│   ├── wal/                          # Write-Ahead Log для crash recovery
│   │   └── <url-encoded-path>.wal.jsonl
│   └── cache/
│       └── file_tree.json            # Кеш дерева файлов (перестраивается при запуске)
│
├── .sync/                            # СИНХРОНИЗИРУЕТСЯ между устройствами
│   ├── vault/                        # Oplog'и для пользовательских файлов
│   │   ├── welcome.md/               # Одна папка = один файл vault
│   │   │   ├── <device-uuid-1>.oplog.jsonl
│   │   │   └── <device-uuid-2>.oplog.jsonl
│   │   └── notes/
│   │       └── daily/
│   │           └── 2024-01-15.md/
│   │               ├── <device-uuid-1>.oplog.jsonl
│   │               └── <device-uuid-2>.oplog.jsonl
│   ├── daily-notes/                  # (будущее) Oplog'и для встроенных дневных заметок
│   ├── calendar/                     # (будущее) Oplog'и для встроенного календаря
│   └── meta/                         # (будущее) Синхронизируемая мета-информация
│
├── vault/                            # Пользовательские .md файлы — актуальные snapshots
│   ├── welcome.md
│   └── notes/
│       ├── daily/
│       │   └── 2024-01-15.md
│       └── projects/
│           └── noetec.md
│
├── daily-notes/                      # (будущее) Встроенные дневные заметки
└── calendar/                         # (будущее) Встроенные данные календаря
```

**Ключевые свойства структуры:**

- `vault/` и `.sync/vault/` — зеркальная структура путей. `vault/notes/a.md` ↔ `.sync/vault/notes/a.md/<device>.oplog.jsonl`
- `.noetec/` — не синхронизируется. Локальное состояние устройства.
- `.sync/` — синхронизируется целиком (например, через Dropbox). Содержит только oplog'и и мету.
- Будущие встроенные модули (`daily-notes/`, `calendar/`) — отдельные namespace, не пересекаются с `vault/`.

---

## Формат .md файла (YAML frontmatter)

Каждый .md файл в `vault/` начинается с YAML frontmatter-блока:

```markdown
---
id: a1b2c3d4-5678-90ab-cdef-1234567890ab
content_hash: sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
modified: 2024-01-15T10:30:00.000Z
modified_by: f47ac10b-58cc-4372-a567-0e02b2c3d479
---

::: {#block-abc123}
# Заголовок документа
:::

::: {#block-def456}
Текст параграфа с **bold** и *italic*.
:::
```

**Поля frontmatter:**

| Поле | Описание |
|---|---|
| `id` | UUID документа. Стабилен при переименованиях/перемещениях. |
| `content_hash` | SHA-256 от содержимого файла **после** frontmatter-блока (т.е. от блоков). Используется для детекции внешних изменений. |
| `modified` | ISO 8601 timestamp последнего сохранения. |
| `modified_by` | UUID устройства, сделавшего последнее сохранение. |

**Детекция внешних изменений:**
Если `content_hash` в frontmatter ≠ реальный SHA-256 содержимого файла —
файл был изменён внешним инструментом. Приложение создаёт oplog запись
от имени текущего устройства с diff изменений.

---

## Два потока мониторинга

| Поток | Наблюдает | Цель | Механизм (MVP) |
|---|---|---|---|
| **Sync watcher** | `.sync/vault/` | Новые oplog записи от других устройств | Polling по lastModified oplog файлов |
| **Vault watcher** | `vault/` | Внешние правки .md файлов (другими редакторами) | Сравнение `content_hash` из frontmatter с реальным hash |

---

## HLC (Hybrid Logical Clock)

**Формат:** `<physical_time_ms>-<counter_hex>-<device_uuid_short>`

Пример: `1705312200000-0001-a1b2c3d4`

**Свойства:**
- **Causality**: если A произошло до B на одном устройстве, HLC(A) < HLC(B) лексикографически
- **Uniqueness**: counter + device_id гарантируют уникальность даже при одинаковом wall clock
- **Approximation**: привязка к физическому времени для человекочитаемости
- **No coordination**: не требует связи между устройствами при генерации

**Алгоритм:**
```
create(device):
  physical = max(wallClock(), lastHLC.physical)
  counter  = (physical == lastHLC.physical) ? lastHLC.counter + 1 : 0
  return HLC(physical, counter, device)

receive(remote, device):
  physical = max(wallClock(), remote.physical, lastHLC.physical)
  counter  = (все равны) ? min(lastHLC, remote).counter + 1 : 0 (или 1 если совпадают два)
  return HLC(physical, counter, device)
```

---

## Формат записи в oplog (.jsonl)

Каждая строка — один JSON объект (операция):

```json
{"v":1,"hlc":"1705312200000-0001-a1b2c3d4","parent":"1705312195000-0003-e5f6g7h8","type":"block_update","block_id":"def456","data":{"segments":[{"text":"Новый текст","format":0}]},"file_hash":"sha256:abc123..."}
```

**Поля:**

| Поле | Тип | Описание |
|---|---|---|
| `v` | int | Версия формата (для будущей миграции) |
| `hlc` | string | HLC timestamp этой операции |
| `parent` | string? | HLC предыдущей операции в цепочке (null для первой) |
| `type` | string | Тип операции (см. ниже) |
| `*` | any | Данные специфичные для типа операции |
| `file_hash` | string? | SHA-256 snapshot файла после `save` операции (только для type=`save`) |

**Типы операций:**

| Тип | Данные | Описание |
|---|---|---|
| `file_create` | `{initial_blocks, title}` | Создание файла (первая запись в oplog) |
| `file_delete` | `{}` | Пометка файла как удалённого |
| `file_rename` | `{old_path, new_path}` | Переименование/перемещение |
| `block_insert` | `{block_id, after_block_id?, block_type, segments}` | Вставка нового блока |
| `block_delete` | `{block_id}` | Удаление блока |
| `block_update` | `{block_id, segments}` | Обновление содержимого блока |
| `block_move` | `{block_id, after_block_id?}` | Перемещение блока (null = в начало) |
| `save` | `{file_hash}` | Точка сохранения — группирует предшествующие операции |
| `external_edit` | `{file_hash, diff_blocks}` | Внешнее изменение файла, детектированное по content_hash |
| `merge` | `{parent_a, parent_b, file_hash}` | Объединение расходящихся веток (ручной или авто резолв) |

---

## Merge алгоритм (обзор)

1. **Собрать** все `.oplog.jsonl` файлы из `.sync/vault/<path>/`
2. **Построить DAG** из операций по `parent` ссылкам
3. **Найти heads** — последние операции каждого устройства
4. **Определить топологию:**
   - Один head = потомок другого → **fast-forward** (нет конфликта, просто применить)
   - Heads расходятся → **3-way merge**
5. **3-way merge:**
   - Найти LCA (Lowest Common Ancestor) расходящихся heads
   - Реконструировать состояние в LCA, в head-ours, в head-theirs
   - Вычислить diffs: LCA→ours, LCA→theirs
   - Смержить diffs:
     - Разные блоки → применить оба (нет конфликта)
     - Один блок, один удалил / другой изменил → по политике (удаление приоритетнее? или изменение?)
     - Один блок, оба изменили → попробовать line-level merge содержимого
     - Line-level merge неудачен → conflict marker в блоке + `merge` операция с флагом `needs_resolution`
6. **Обновить** snapshot в `vault/<path>` и frontmatter

---

## Этапы реализации

| # | Файл | Что реализуется | После этапа |
|---|---|---|---|
| 1 | `01-vault-foundation.md` | Модели, HLC, VaultService, frontmatter, device identity | Vault создаётся, файлы читаются/пишутся |
| 2 | `02-ui-sidebar-filetree.md` | Sidebar, file tree, навигация, диалоги создания/удаления | Работающий файловый менеджер |
| 3 | `03-persistence-autosave.md` | Save/load, autosave, WAL, crash recovery, session | Полноценный файловый редактор |
| 4 | `04-oplog-engine.md` | Oplog writer/reader, diff engine, DAG, state reconstruction | История изменений готова к синхронизации |
| 5 | `05-sync-merge.md` | Polling .sync/, merge engine, conflict resolution UI | Синхронизация через Dropbox и аналоги |
| 6 | `06-external-vault.md` | file_picker, платформенные абстракции, multi-vault | Выбор произвольной папки на всех платформах |

**После этапа 3** — приложение уже является функциональным офлайн-редактором.
**После этапа 5** — полноценная синхронизация через любой file sync сервис.
**Этап 6** — production-ready на всех платформах.

---

## Новые пакеты по этапам

| Этап | Пакет | Назначение |
|---|---|---|
| 1 | `path_provider` | application documents directory |
| 1 | `crypto` | SHA-256 для content_hash |
| 1 | `yaml` | Парсинг YAML frontmatter |
| 3 | `path_provider` | уже добавлен |
| 6 | `file_picker` | Выбор папки (dialog) |
| 6 | `saf` | Android Storage Access Framework |
| 6 | `secure_bookmark` | iOS/macOS sandbox persistent access |
| 6 | `flutter_secure_storage` | Хранение закладок в Keychain |
| 6 | `shared_preferences` | Хранение пути vault (desktop) |
| Все | `watcher` | File system watching (альтернатива polling) |
