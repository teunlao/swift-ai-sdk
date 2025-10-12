# Снимок Vercel AI SDK (референс для Swift-порта)

## Базовые параметры репозитория
- **Исходный репозиторий**: https://github.com/vercel/ai
- **Коммит**: 77db222eeded7a936a8a268bf7795ff86c060c2f (состояние на 12 октября 2025 года)
- **Основный пакет**: `packages/ai`
- **Опубликованная версия**: `6.0.0-beta.42` (см. `packages/ai/package.json`)

## Карта модулей верхнего уровня
- `packages/ai/src`
  - `generate-text`, `generate-object`, `generate-image`, `generate-speech` — точка входа в оркестрацию.
  - `text-stream`, `ui-message-stream` — вспомогательные утилиты для сборки потоков.
  - `tool`, `tool/mcp` — описание инструментов, интеграция с MCP.
  - `registry`, `model`, `prompt` — реестр моделей, стандартизация промптов.
  - `types`, `error`, `telemetry`, `logger`, `util` — общая инфраструктура.
  - `agent`, `middleware`, `ui` — интеграции с фреймворками (Next.js, React и др.).
- `packages/provider` и пакеты конкретных провайдеров (`openai`, `anthropic`, `google`, `groq`, …) реализуют транспортные адаптеры.
- `packages/provider-utils` — общие HTTP-хелперы и валидация схем.
- `packages/gateway`, `packages/ai-elements` и др. — надстройки на базе ядра.

## Технологические заметки
- Язык: TypeScript (ESM) с активным использованием union-типов и дискриминированных объединений.
- Асинхронность: Promises + `ReadableStream` (web) / `AsyncIterable` (node). Хелперы приводят разные протоколы к единому `LanguageModelV2StreamPart`.
- Тесты: Vitest + снапшоты (`__snapshots__`), интеграционные тесты через мок fetch и ответов провайдеров.
- Сборка: Turborepo, tsup, модульные tsconfig.

## Выводы для Swift-порта
- Сохраняем паритет API у `generateText` / `streamText`, включая коллбеки (`onStepFinish`, `onFinish`, `toolChoice` и т.д.).
- Переводим TypeScript-union'ы в Swift-enum'ы с ассоциированными значениями (`LanguageModelV2StreamPart`, `ToolChoice` и др.).
- Воссоздаём реестр провайдеров и идентификаторы моделей (`provider:model`) через структуры/enum'ы Swift.
- Заменяем `fetch`/`ReadableStream` на `URLSession` + `AsyncThrowingStream`.
- Переносим тестовые сценарии на Swift Testing, при возможности подхватывая те же фикстуры.
- Документацию синхронизируем с Vercel, фиксируя Swift-специфику отдельно.

## Ближайшие шаги
1. Спроектировать структуру Swift-модулей, отражающую `packages/ai/src` (Core, Streams, Tools, Registry, Providers).
2. Описать базовые типы и enum'ы (`LanguageModelV2`, `LanguageModelV2StreamPart`, `ToolDefinition`, и т.д.).
3. Определить минимальную HTTP-абстракцию под много провайдеров.
4. Отобрать ключевые тестовые сценарии для начала (happy-path `generate-text`, вызов инструментов, стриминг).
- Контракты `LanguageModelV2` и `LanguageModelV3` сосуществуют: V2 адаптируется к V3 через `resolveModel`. Swift-порт обязан реализовать тот же слой совместимости.
