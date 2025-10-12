# План тестового покрытия Swift AI SDK

## Цель
Воспроизвести тестовый контур Vercel AI SDK (Vitest) в среде Swift, добавив проверки для Swift-конкурентности и Codable-сериализации.

## Структура тестов
- `Tests/CoreTests` — generateText/streamText, оркестрация шагов, обработка stop-условий, tool-choice, обработка ошибок.
- `Tests/StreamsTests` — парсер SSE, преобразования `StreamTextResult`, UI-потоки.
- `Tests/ToolsTests` — описание инструментов, вызовы, сериализация tool input/output.
- `Tests/ProvidersTests` — HTTP-вызовы и мапперы для каждого провайдера (OpenAI, Anthropic, Google…).
- `Tests/RegistryTests` — регистрация моделей, строковые ID, кастомные провайдеры.
- `Tests/TelemetryTests` — интеграция с OpenTelemetry (trace/span).
- `Tests/Integration` — сценарии end-to-end: стрим + tool + финальный ответ.

## Источники сценариев
- Vitest-файлы из `packages/ai/src/**/__tests__` / `__snapshots__` — переносим 1:1.
- Тесты `provider-utils`, `provider` — проверяем HTTP-заголовки, SSE, ошибки провайдеров.
- `test-server` — используем как референс для моков; в Swift заменяем на `URLProtocol` + кастомный SSE-мок.

## Инфраструктура Swift-тестов
- Фреймворк: Swift Testing (`swift test`), при необходимости `@testable import` целевых модулей.
- Моки HTTP: `URLProtocol` + фикстуры JSON из оригинальных snapshot'ов.
- SSE-стрим: `AsyncThrowingStream` с тестовым генератором событий.
- Ассерты: сравнение JSON/строк, проверка последовательности стрим-частей, ожиданий по `finishReason` и usage.
- Живые запросы к внешним провайдерам не выполняем (как и в TypeScript-версии): все тесты синтетические, опираются на моки и фикстуры.

## Swift-специфичные проверки
- Actor-изоляция и cancel: тесты на корректное завершение `streamText` при `Task.cancel()`.
- Сериализация `Codable`: round-trip для ключевых типов (`GenerateTextResult`, `StreamTextResult`, `ToolCall`).
- Тесты на отсутствие race-condition при одновременных вызовах (используем `TaskGroup`).

## Порядок миграции
1. Переносим базовые happy-path тесты `generate-text` и `stream-text` (без tools).
2. Добавляем tool invocation + шаги оркестрации (максимально повторяем TypeScript логику).
3. Реализуем SSE-моки и тесты `text-stream`, `ui-message-stream`.
4. Подключаем OpenAI-провайдера: проверка запросов, response parsing.
5. Расширяем на остальных провайдеров (Anthropic, Google, Groq…), используя их TypeScript тесты.
6. Покрываем registry/telemetry, добавляем Swift-only проверки.
7. End-to-end сценарии, включая ошибки, stopConditions, toolChoice.

## Документация прогресса
- Вести таблицу соответствия: «Vitest файл → Swift тесты (статус)» в этом же документе.
- Фиксировать отклонения (если API Swift вынужден отличаться от TypeScript) и причину.
- Все фикстуры хранить в `Tests/Fixtures` с ссылкой на оригинальное местоположение.
