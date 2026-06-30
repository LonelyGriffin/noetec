# Noetec

!**СМОТРИ ПРАВИЛА .kilo\rules**

## Языковые настройки

**Все ответы должны быть на русском языке.**
**Все комментарии в коде и документация должны быть на английском языке.**
**Все планы для конкретных реализаций должны быть написаны на русском**

## Оркестратор скиллов

**В самом начале каждого разговора** если в проекте есть скилл оркестратор скиллов, вызывай его. Например: `skill-orchestrator`. Это обязательно.

## Обзор проекта

Виденье проекта можно посмотреть в docs/FIRST_VISION.md, архитектуру в docs/ARCHITECTURE.md.
Состояние системы ввода и редактирования описано в docs/USER_INPUT_SYSTEM.md.

### Ключевые технологии

- **Flutter**: кроссплатформенный UI (macOS primary)
- **get_it**: DI-контейнер
- **listen_it / watch_it**: реактивное управление состоянием
- **json_serializable + build_runner**: кодогенерация
- **flutter_secure_storage**: безопасное хранение
- **markdown**: рендеринг Markdown
- **uuid**: генерация идентификаторов

### Доступные команды

- `dart run scripts/lint.dart` — полный lint (format + analyze + copyright)
- `dart run scripts/format.dart` — форматирование всего проекта (длина строки 180, из `.dart-format`)
- `dart analyze` — статический анализ
- `dart format .` — форматирование кода
- `dart format --set-exit-if-changed .` — проверка форматирования (CI)
- `flutter test` — запуск всех тестов
- `flutter test --coverage` — тесты с покрытием
- `dart run build_runner build` — кодогенерация (json_serializable и др.)
- `dart run build_runner watch` — кодогенерация в watch-режиме

**Не запускай само приложение - я сам буду его запускать для проверки что оно запускается**

## Структура кода

```
lib/
├── app/                          # Application layer (оркестрация и навигация)
│   ├── configure_di.dart          # Регистрация зависимостей в get_it
│   ├── main_app_widget.dart       # Корневой виджет приложения
│   └── bootstrap_widget.dart      # Бутстрап-виджет
├── entity/                        # Domain entities
│   ├── page/                      # Page entities (mutable для редактирования)
│   │   ├── block/                 # Block entities (TextBlockEntity с segments)
│   │   ├── page.dart              # PageEntity (blocks, selection)
│   │   └── selection.dart         # Selection hierarchy
│   └── vault/                     # Vault entities (immutable)
├── systems/                       # Systems layer (фичи с reactive state)
│   ├── layout/                    # UI layout system
│   ├── markdown_system/           # Markdown parser/serializer
│   ├── page_system/               # Page editing, selection, clipboard
│   ├── user_input_system/         # IME, keyboard, pointer, clipboard handlers
│   └── vault/                     # Vault management
├── service/                       # Infrastructure services
│   ├── id_service.dart            # IIdService + IdService
│   ├── file_system_service.dart   # IFileSystemService + FileSystemServiceImpl
│   └── settings_service.dart      # ISettingsService + SettingsServiceImpl
├── view/                          # Presentation
│   └── screens/
└── main.dart                      # Точка входа
```

## Тестирование

### Типы тестов

- **Юнит-тесты**: покрывают domain-логику конкретных функций классов. 
- **Интеграционные тесты**: покрывают определеные юзер кейсы тестируючие в комплексе все системы

**Не нужно писать тесты на тривиальную логику, малозначимые участки приложения. Дублирующие тесты.**

### Структура тестов

```
test/
└── lib/
    └── <зеркало структуры lib/>
```

### Интеграционные тесты (integration_test/)

**Принципы:**
- Тест = **пользовательский сценарий**, не техническая проверка компонента
- Не дублировать проверки между сценариями — каждый тест проверяет то, что не покрывается в других
- Проверять **содержимое файлов** на диске, а не только факт существования
- **TDD**: сначала пишем тест (ожидаемо красный), реализация — в отдельной сессии. **Не трогать production-код при написании тестов**
- Имена хелпер-функций отражают пользовательский сценарий, а не внутреннюю технологию (например, `expectCrashRecoveryLogExists`, а не `expectWalFileExists`)

**Структура:**
```
integration_test/
├── app_test.dart              # Сценарии (testWidgets)
└── helpers/
    ├── widget_finders.dart     # UI-файндеры
    ├── vault_assertions.dart   # Проверки файлов хранилища
    ├── session_assertions.dart # Проверки session.json
    ├── key_assertions.dart     # Проверки криптографии
    └── test fixtures           # InMemory-реализации, VaultFolderFixture
```

### Запуск

```bash
# Все тесты
flutter test

# Конкретный файл
flutter test test/lib/entity/document/document_test.dart

# С покрытием
flutter test --coverage
```

## Конфигурация

DI-контейнер `get_it` настраивается в `lib/app/configure_di.dart`. Все зависимости регистрируются там.

## Соглашения по разработке

### Качество кода

- Статический анализ: `dart analyze` (конфиг: `analysis_options.yaml`)
- Форматирование: `dart format`
- Типизация: строгий режим, `flutter_lints`
- Длина строки: 180 символов

### Используемые паттерны

- **Interface-sealed**: `abstract interface class IXxxService` + `XxxServiceImpl`
- **Immutable state**: команды создают новые объекты, никаких мутаций
- **DI через get_it**: вся конфигурация в `configure_di.dart`

## Подводные камни / Что не делать

- **PageEntity и TextBlockEntity mutable** — они используют `ListNotifier` и `ValueNotifier` для производительности. Другие entity (Vault) остаются immutable.
- **Не использовать `print()`** — использовать `package:logging`
- **Не редактировать сгенерированные файлы** в `*.g.dart`, `*.freezed.dart`
- **Не нарушать слои** — `entity/` не должен импортировать Flutter (кроме `flutter/foundation.dart` для `ValueNotifier`)
- **Не использовать `setState()` в ViewModels** — использовать Stream-based реактивность
- **IME sync** — после мутаций текста/курсора в handlers вызывать `ime.syncImeState(pageId)`

## Типичные задачи разработки

### Добавление нового сервиса

1. Создать файл `lib/service/<name>_service.dart` с интерфейсом и реализацией в одном файле (`abstract interface class I{Name}Service` + `{Name}ServiceImpl`)
2. Зарегистрировать в `lib/app/configure_di.dart`
3. Написать тесты с fake-реализацией
