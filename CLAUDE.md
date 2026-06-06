# Noetec

!**СМОТРИ ПРАВИЛА .kilo\rules**

## Языковые настройки

**Все ответы должны быть на русском языке.**
**Все комментарии в коде и документация должны быть на английском языке.**
**Все планы для конкретных реализаций должны быть написаны на русском**

## Оркестратор скиллов

**В самом начале каждого разговора** если в проекте есть скилл оркестратор скиллов, вызывай его. Например: `skill-orchestrator`. Это обязательно.

## Обзор проекта

Виденье проекта можно посмотреть в docs/FIRST_VISION.md а архитектуру в docs/ARCHITECTURE.md

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
├── entity/                        # Domain entities (immutable, без Flutter зависимостей)
├── systems/                       # Systems layer (фичи с reactive state и commands)
│   └── vault/                     # Фича vault management
├── service/                       # Infrastructure services (интерфейсы + реализации)
│   ├── id_service.dart            # IIdService + IdService
│   ├── file_system_service.dart   # IFileSystemService + FileSystemServiceImpl
│   ├── settings_service.dart      # ISettingsService + SettingsServiceImpl
│   └── vault_repository.dart      # IVaultRepository + VaultRepositoryImpl
├── view/                          # Presentation
│   └── screens/
└── main.dart                      # Точка входа
```

## Тестирование

### Типы тестов

- **Юнит-тесты**: покрывают domain-логику конкретных функций классов
- **Интеграционные тесты**: покрывают определеные юзер кейсы тестируючие в комплексе все системы

### Структура тестов

```
test/
└── lib/
│   └── <зеркало структуры lib/>
└── integration
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

- **Не мутировать состояние** — создавать новые immutable объекты через `.copyWith()` или конструкторы
- **Не использовать `print()`** — использовать `package:logging`
- **Не редактировать сгенерированные файлы** в `*.g.dart`, `*.freezed.dart`
- **Не нарушать слои** — `entity/` не должен импортировать Flutter
- **Не использовать `setState()` в ViewModels** — использовать Stream-based реактивность

## Типичные задачи разработки

### Добавление нового сервиса

1. Создать файл `lib/service/<name>_service.dart` с интерфейсом и реализацией в одном файле (`abstract interface class I{Name}Service` + `{Name}ServiceImpl`)
2. Зарегистрировать в `lib/app/configure_di.dart`
3. Написать тесты с fake-реализацией
