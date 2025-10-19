# Swift AI SDK Playground

CLI инструмент для ручного тестирования Swift AI SDK с реальными провайдерами.

## Возможности

- ✅ Синхронный и потоковый режимы
- ✅ Поддержка инструментов (tools)
- ✅ Несколько провайдеров (OpenAI, Gateway)
- ✅ JSON и текстовый вывод
- ✅ Verbose режим для отладки
- ✅ Чтение промптов из файлов или stdin

## Быстрый старт

### 1. Настройка

Создайте `.env` файл в корне проекта:

```env
# OpenAI (рекомендуется)
OPENAI_API_KEY=sk-proj-...

# Или используйте Vercel AI Gateway
VERCEL_AI_API_KEY=your_gateway_key
AI_GATEWAY_BASE_URL=https://ai-gateway.vercel.sh/v1/ai
```

### 2. Сборка

```bash
swift build
```

### 3. Запуск

```bash
# Простой запрос
swift run playground chat --provider openai --model gpt-4o-mini \
  --prompt "Hello, how are you?"

# С потоковым выводом
swift run playground chat --stream --provider openai --model gpt-4o-mini \
  --prompt "Write a haiku about Swift"
```

## Использование инструментов (Tools)

### Базовый пример

```bash
swift run playground chat --with-tools --provider openai --model gpt-4o-mini \
  --prompt "What is the weather in San Francisco? Also calculate 25 times 4"
```

**Результат:**
```
📊 Результаты:

Steps: 1
Finish reason: tool-calls
Usage: 112 tokens

[0] 🔧 Tool: getWeather
       Input: {"location": "San Francisco"}
[1] 🔧 Tool: calculate
       Input: {"operation": "multiply", "a": 25, "b": 4}
[2] ✅ Result: getWeather
       Output: {"location": "San Francisco", "temperature": 65, "unit": "fahrenheit"}
[3] ✅ Result: calculate
       Output: {"result": 100, "operation": "multiply"}
```

### Streaming с инструментами

```bash
swift run playground chat --stream --with-tools \
  --provider openai --model gpt-4o-mini \
  --prompt "Weather in Paris and calculate 100 divided by 5"
```

**Результат:**
```
🔧 [Tool Call] getWeather
✅ [Tool Result] getWeather

🔧 [Tool Call] calculate
✅ [Tool Result] calculate

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 Step 1 завершён
   Reason: tool-calls
   Usage: 112 tokens
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🏁 Завершено
   Final reason: tool-calls
   Total usage: 112 tokens
   Steps: 1
```

### Доступные демо-инструменты

#### `getWeather(location: string)`
Получение погоды по локации (симулированные данные).

**Пример:**
```bash
swift run playground chat --with-tools --provider openai --model gpt-4o-mini \
  --prompt "What's the weather in London?"
```

#### `calculate(operation: string, a: number, b: number)`
Калькулятор для базовых операций.

**Операции:** `add`, `subtract`, `multiply`, `divide`

**Пример:**
```bash
swift run playground chat --with-tools --provider openai --model gpt-4o-mini \
  --prompt "Calculate 15 + 27"
```

## Опции команды

### Глобальные флаги

```bash
--verbose              # Детальное логирование
--env-file <path>      # Путь к .env файлу (по умолчанию: корень проекта)
```

### Опции chat команды

```bash
# Обязательные
-m, --model <model>    # ID модели (gpt-4o-mini, gpt-4o, claude-3-5-sonnet-20241022, и т.д.)

# Источник промпта (один из):
-p, --prompt <text>    # Промпт одной строкой
--input-file <path>    # Читать из файла
--stdin                # Читать из стандартного ввода

# Опциональные
-P, --provider <name>  # Провайдер (openai, gateway) [по умолчанию: gateway]
-s, --stream           # Потоковый вывод
--json-output          # Вывод в JSON формате
--with-tools           # Включить демо-инструменты (weather, calculator)
```

## Примеры использования

### Простые запросы

```bash
# Базовый запрос
swift run playground chat --provider openai --model gpt-4o-mini \
  --prompt "Explain quantum computing in one sentence"

# С потоком
swift run playground chat --stream --provider openai --model gpt-4o-mini \
  --prompt "Write a short story about AI"

# JSON вывод
swift run playground chat --json-output --provider openai --model gpt-4o-mini \
  --prompt "What is 2+2?"
```

**JSON результат:**
```json
{
  "finishReason": "stop",
  "text": "2 + 2 equals 4.",
  "usage": {
    "cachedInputTokens": 0,
    "inputTokens": 14,
    "outputTokens": 9,
    "reasoningTokens": 0,
    "totalTokens": 23
  },
  "warnings": []
}
```

### Работа с файлами

```bash
# Из файла
echo "Explain what is Swift AI SDK" > prompt.txt
swift run playground chat --provider openai --model gpt-4o-mini \
  --input-file prompt.txt

# Из stdin
echo "What is the capital of France?" | \
  swift run playground chat --stdin --provider openai --model gpt-4o-mini
```

### С инструментами

```bash
# Синхронный режим
swift run playground chat --with-tools --provider openai --model gpt-4o-mini \
  --prompt "Weather in Tokyo and calculate 50 * 2"

# Streaming режим
swift run playground chat --stream --with-tools \
  --provider openai --model gpt-4o-mini \
  --prompt "Weather in Berlin and divide 144 by 12"

# JSON вывод с tools
swift run playground chat --with-tools --json-output \
  --provider openai --model gpt-4o-mini \
  --prompt "Calculate 7 + 8"
```

**JSON результат с tools:**
```json
{
  "finishReason": "tool-calls",
  "steps": 1,
  "text": "",
  "toolCalls": 1,
  "toolResults": 1,
  "usage": {
    "cachedInputTokens": 0,
    "inputTokens": 118,
    "outputTokens": 22,
    "reasoningTokens": 0,
    "totalTokens": 140
  }
}
```

### Verbose режим

```bash
swift run playground chat --verbose --stream --with-tools \
  --provider openai --model gpt-4o-mini \
  --prompt "What's the weather?"
```

**Вывод:**
```
[debug] Инициализация команды chat
[debug] Использую провайдера openai (model=gpt-4o-mini)
[debug] Streaming с 2 инструмент(ами)
[debug] Unhandled stream part: start
[debug] Unhandled stream part: startStep(...)
[debug] Unhandled stream part: toolInputStart(id: call_..., toolName: getWeather)
[debug] Unhandled stream part: toolInputDelta(id: call_..., delta: {...})
...
🔧 [Tool Call] getWeather
[debug]    Args: {"location": "..."}
✅ [Tool Result] getWeather
[debug]    Output: {"temperature": 72, ...}
```

## Требования

- **macOS 11+** для базовых функций
- **macOS 13+** для использования tools (`--with-tools`)
- Swift 6.1+

## Архитектура

```
SwiftAISDKPlayground/
├── Commands/
│   └── ChatCommand.swift           # Основная команда
├── Environment/
│   ├── EnvironmentLoader.swift     # Загрузка .env
│   └── PlaygroundConfiguration.swift
├── Providers/
│   ├── Gateway/
│   │   └── GatewayLanguageModel.swift
│   ├── OpenAI/
│   │   └── OpenAILanguageModel.swift
│   └── ProviderFactory.swift
└── Utils/
    ├── PlaygroundLogger.swift
    └── PlaygroundVersion.swift
```

## Поддерживаемые провайдеры

### OpenAI (рекомендуется)

```env
OPENAI_API_KEY=sk-proj-...
# Опционально:
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_ORGANIZATION=org-...
OPENAI_PROJECT=proj_...
```

**Модели:** `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo`, `gpt-3.5-turbo`

### Vercel AI Gateway

```env
VERCEL_AI_API_KEY=your_key
AI_GATEWAY_BASE_URL=https://ai-gateway.vercel.sh/v1/ai
```

### Планируется

- Anthropic (Claude)
- Google (Gemini)
- Groq
- OpenRouter

## Ограничения

- Демо-инструменты используют симулированные данные
- Streaming с tools требует macOS 13.0+
- Один провайдер за раз

## Отладка

### Проверка API ключей

```bash
# Проверьте, что ключ загружен
swift run playground chat --verbose --provider openai \
  --model gpt-4o-mini --prompt "test"
```

Если ключ не найден:
```
❌ Не найден API ключ для провайдера openai.
   Добавьте его в переменные окружения или .env.
```

### Проверка версии

```bash
swift run playground --version
```

### Справка

```bash
swift run playground --help
swift run playground chat --help
```

## Примеры workflow

### Быстрое тестирование SDK

```bash
# 1. Простой запрос
swift run playground chat --provider openai --model gpt-4o-mini \
  --prompt "Hello"

# 2. С streaming
swift run playground chat --stream --provider openai --model gpt-4o-mini \
  --prompt "Count to 5"

# 3. С tools
swift run playground chat --with-tools --provider openai --model gpt-4o-mini \
  --prompt "Weather in NYC and calculate 10 + 15"

# 4. JSON вывод для автоматизации
swift run playground chat --json-output --provider openai --model gpt-4o-mini \
  --prompt "test" | jq '.usage.totalTokens'
```

### Интеграция в скрипты

```bash
#!/bin/bash

# Тестирование нескольких моделей
for model in gpt-4o-mini gpt-4o; do
  echo "Testing $model..."
  swift run playground chat --provider openai --model "$model" \
    --prompt "Say 'OK'" --json-output | jq -r '.text'
done
```

## Связанные документы

- [playground.md](../../plan/playground.md) - План разработки
- [Package.swift](../../Package.swift) - Конфигурация SwiftPM
- [.env.sample](../../.env.sample) - Пример конфигурации

---

**Версия:** 1.0.0
**Обновлено:** 2025-10-19
