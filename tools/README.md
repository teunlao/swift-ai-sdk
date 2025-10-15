# Swift Test Runner

**Умный test runner с детекцией зависаний, чистым выводом и отладкой race conditions.**

## Ключевые features

- ✅ **Чистый вывод** - Только итоговая сводка и failures (без build noise)
- ⏱️  **Встроенный timeout** - Детектит зависания (race conditions)
- 🎯 **Умная фильтрация** - Include/exclude тестов по паттернам
- 🧹 **Авто-cleanup** - Убивает zombie swiftpm-testing-helper процессы
- 📊 **Фокус на результат** - "1114 тестов прошли" или детальные failures

## Проблема

При большом количестве тестов (1000+) сложно:
- **Найти проблемные тесты** при зависании (race conditions)
- **Детектить timeout** - обычный swift test просто висит
- **Видеть что важно** - build output забивает весь экран
- **Временно исключить** подозрительные тесты без правки кода

## Решение

Node.js скрипт с умным парсингом, timeout detection и clean output.

## Конфигурации

### `test-runner.default.config.json` (DEFAULT)
**Используется автоматически если не указан --config**
- Запускает **ВСЕ тесты**
- Timeout: 15 секунд
- Для ежедневной разработки

### `test-runner.exclude-embed.config.json`
- Исключает EmbedTests/EmbedManyTests (race conditions)
- Для отладки других тестов

### `test-suspicious.config.json`
- Запускает **ТОЛЬКО** проблемные тесты
- Для воспроизведения race conditions

### `test-binary-search.config.json`
- Для бинарного поиска проблемных тестов
- Инструкции внутри файла

## Установка

```bash
cd tools
chmod +x test-runner.js
```

## Быстрый старт

1. **Запустить ВСЕ тесты** (использует default конфиг):
```bash
./test-runner.js
```

Вывод:
```
🧪 Running: swift test
⏱️  Timeout: 15000ms

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ ALL 1114 TESTS PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Или если timeout:
```
⏱️  TIMEOUT: Tests did not complete in time!
❌ This indicates race conditions or async issues
```

2. **С кастомным конфигом**:
```bash
./test-runner.js --config test-runner.exclude-embed.config.json
```

3. **Посмотреть все тесты**:
```bash
./test-runner.js --list
```

## Режимы работы

### 1. Исключить тесты (exclude)

Запустить **ВСЕ тесты КРОМЕ** указанных в списке:

```json
{
  "mode": "exclude",
  "tests": [
    "SwiftAISDKTests.HandleUIMessageStreamFinishTests/*",
    "SwiftAISDKTests.ReadUIMessageStreamTests/*",
    "*.CreateUIMessageStreamTests/mergesMultipleStreams"
  ],
  "parallel": true
}
```

**Использование**: Вычленить проблемные тесты при зависании.

### 2. Включить только (include)

Запустить **ТОЛЬКО** указанные тесты:

```json
{
  "mode": "include",
  "tests": [
    "AISDKProviderTests.*",
    "SwiftAISDKTests.DelayTests/*"
  ],
  "parallel": false
}
```

**Использование**: Протестировать конкретную функциональность.

### 3. Последние N тестов (last)

```json
{
  "mode": "last",
  "count": 50,
  "parallel": true
}
```

**Использование**: Быстро проверить недавно добавленные тесты.

### 4. Первые N тестов (first)

```json
{
  "mode": "first",
  "count": 100,
  "parallel": false
}
```

### 5. Все тесты (all)

```json
{
  "mode": "all",
  "parallel": true,
  "verbose": true
}
```

## Паттерны фильтрации

### Wildcard синтаксис:

- `*` - любая последовательность символов
- `?` - один любой символ
- `.` - точка (экранируется автоматически)

### Примеры:

```json
{
  "tests": [
    // Весь test suite
    "SwiftAISDKTests.HandleUIMessageStreamFinishTests/*",

    // Все тесты во всех пакетах с именем CreateUIMessageStreamTests
    "*.CreateUIMessageStreamTests/*",

    // Конкретный тест
    "SwiftAISDKTests.DelayTests/delayWithSignal",

    // Все тесты с "Finish" в названии suite
    "*Finish*/*",

    // Все тесты в пакете AISDKProviderTests
    "AISDKProviderTests.*"
  ]
}
```

## Опции конфига

```json
{
  "mode": "exclude",             // exclude, include, all, last, first
  "exclude": ["pattern1", "..."], // Массив паттернов для exclude mode
  "include": ["pattern1", "..."], // Массив паттернов для include mode
  "parallel": true,               // Запуск в parallel режиме
  "verbose": false,               // Детальный вывод
  "timeout": 15000,               // Timeout в ms (default: 15000)
  "count": 20                     // Для режимов last/first
}
```

**Важно:**
- Используйте `exclude` для mode="exclude" (семантично)
- Используйте `include` для mode="include" (семантично)
- `tests` и `patterns` - legacy (работают но deprecated)

## Командная строка

```bash
# Показать помощь
./test-runner.js --help

# Создать дефолтный конфиг
./test-runner.js --init

# Показать список всех тестов
./test-runner.js --list

# Запустить с кастомным конфигом
./test-runner.js --config my-config.json

# Dry run (показать что будет запущено)
./test-runner.js --dry-run

# Запустить
./test-runner.js
```

## Примеры использования

### Найти проблемный тест при зависании

1. Запустить default конфиг:
```bash
./test-runner.js
```

2. Если timeout - используйте exclude конфиг:
```bash
./test-runner.js --config test-runner.exclude-embed.config.json
```

3. Если всё равно висит - используйте binary search:
```bash
./test-runner.js --config test-binary-search.config.json
```

4. Редактируйте `test-binary-search.config.json` исключая половины тестов

**Пример вывода при failures:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ TEST RUN FAILED
   Total: 1114 tests

🔥 FAILED TESTS (2):

1. should create response with headers and encoded stream
   ✘ Test recorded an issue at CreateUIMessageStreamResponseTests.swift:25:9
   Expectation failed: headers mismatch

2. should handle async consumeSSEStream
   ✘ Test failed after 0.079 seconds with 1 issue
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Протестировать только новый функционал

```json
{
  "mode": "include",
  "tests": [
    "SwiftAISDKTests.UIMessage*"
  ],
  "parallel": false,
  "verbose": true
}
```

### Быстрая проверка последних изменений

```json
{
  "mode": "last",
  "count": 30,
  "parallel": true
}
```

## Отладка

### Посмотреть что будет запущено:

```bash
./test-runner.js --dry-run
```

Вывод:
```
📊 Test Runner Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Mode:           exclude
Total tests:    763
Selected tests: 750
Excluded:       13
Parallel:       Yes
Patterns:       2
  - SwiftAISDKTests.HandleUIMessageStreamFinishTests/*
  - SwiftAISDKTests.ReadUIMessageStreamTests/*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔍 Tests to run:
  AISDKProviderTests.LanguageModelV2CallOptionsTests/full()
  AISDKProviderTests.LanguageModelV2CallOptionsTests/minimal()
  ...
```

### Посмотреть все тесты:

```bash
./test-runner.js --list | grep "UIMessage"
```

## Множественные конфигурации

Создайте разные конфиги для разных сценариев:

```bash
# Конфиг для отладки UI тестов
tools/config-ui-tests.json

# Конфиг для быстрого прогона
tools/config-quick.json

# Конфиг для CI
tools/config-ci.json
```

Запуск:
```bash
./test-runner.js --config config-ui-tests.json
```

## Интеграция с CI

```yaml
# .github/workflows/test.yml
- name: Run tests with exclusions
  run: |
    cd tools
    ./test-runner.js --config config-ci.json
```

## Советы

1. **Бинарный поиск проблемных тестов**: Исключайте половину тестов, пока не найдете проблемный
2. **Сохраняйте рабочие конфиги**: Создавайте отдельные файлы для разных ситуаций
3. **Используйте --dry-run**: Проверяйте что будет запущено перед реальным запуском
4. **Комбинируйте с grep**: `./test-runner.js --list | grep "Pattern"`

## Troubleshooting

### Проблема: тесты зависают

1. Запустите с `--dry-run` чтобы увидеть список
2. Используйте `mode: "exclude"` чтобы исключить подозрительные
3. Бинарным поиском найдите проблемный тест

### Проблема: паттерн не работает

- Проверьте что используете `*` для wildcard
- Используйте `--dry-run` для проверки
- Проверьте точное имя через `--list`

### Проблема: слишком много тестов в фильтре

Скрипт оптимизирует команду группируя по suite. Если проблемы:
- Разбейте на несколько запусков
- Используйте более широкие паттерны

## License

MIT
