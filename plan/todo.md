# TODO (детализированный план портирования)

## Блок A. Инфраструктура (@ai-sdk/provider)
- [ ] Перенести shared типы (`shared/`, `json-value/`, базовые утилиты).
- [ ] Реализовать контракты языковых моделей (`language-model/v2`, `language-model/v3`, middleware).
- [ ] Перенести embedding/speech/image/transcription модельные интерфейсы (версии v2/v3).
- [ ] Перенести ошибки провайдера (`errors/`).
- [ ] Настроить `Provider`/`ProviderRegistry` реализации (`provider/index.ts`).
- [ ] Настроить экспорт и вспомогательные типы (typealiases JSON Schema и др.).

## Блок B. Утилиты провайдера (@ai-sdk/provider-utils)
- [ ] Реализовать id генераторы, работу с UUID (`generate-id`, `createIdGenerator`).
- [ ] Портировать HTTP-хелперы: `fetch-function`, `get-from-api`, `post-to-api`, `response-handler`, `prepare-headers`.
- [ ] Реализовать SSE и EventSource парсер (`parse-json-event-stream`, `EventSourceParserStream` аналог).
- [ ] Портировать работу с API ключами и настройками (`load-setting`, `load-optional-setting`, `parse-provider-options`).
- [ ] Перенести утилиты сериализации/валидации (`schema` ✅, `validate-types` ✅, `parse-json` ✅, `remove-undefined-entries`).
- [ ] Реализовать `withUserAgentSuffix`, `getRuntimeEnvironmentUserAgent` (адаптация под Darwin).
- [ ] Портировать утилиты `resolve`, `delay`, `retry-with-exponential-backoff`, `prepare-retries`.
- [ ] Настроить re-exports и публичный API провайдер-утилит.
- [ ] [executor][TODO] Документация: описать подход к схемам без Zod (использование `Schema.codable`, custom validators, явный UnsupportedStandardSchemaVendorError) и зафиксировать возможность будущего DSL для удобной декларации схем на Swift.

## Блок C. Общие утилиты AI SDK (`packages/ai/src/util`)
- [ ] Портировать стримовые утилиты (`async-iterable-stream`, `create-stitchable-stream`, `simulate-readable-stream`).
- [ ] Реализовать `prepare-retries`, `retry-error`, `serial-job-executor`, `job`.
- [ ] Перенести работу с Data URL, media types, download.
- [ ] Реализовать `fix-json`, `parse-partial-json`, `get-potential-start-index`.
- [ ] Утилиты массивов/объектов (`as-array`, `merge-objects`, `split-array`).

## Блок D. Prompt & Message подготовка (`packages/ai/src/prompt`)
- [ ] Портировать `Prompt`, `ModelMessage`, `CallSettings` структуры.
- [ ] Реализовать `standardizePrompt` и связанные проверки (tests -> Swift Testing).
- [ ] Портировать `prepare-call-settings`, `prepare-tools-and-tool-choice`.
- [ ] Реализовать `convert-to-language-model-prompt`, `create-tool-model-output`.
- [ ] Обработку ошибок (`invalid-message-role-error`, `invalid-data-content-error`, `message-conversion-error`).
- [ ] `wrap-gateway-error` адаптировать под Swift Error.

## Блок E. Генерация текста (`packages/ai/src/generate-text`)
- [ ] Структуры результата (`GenerateTextResult`, `StreamTextResult`, `StepResult`).
- [ ] Портировать `generateText` (орchestration, retries, telemetry, tool steps).
- [ ] Портировать `streamText` (дельты, reasoning, approvals, smooth stream).
- [ ] Реализовать обработку инструментов (`execute-tool-call`, `parse-tool-call`, `tool-result`, `tool-output`).
- [ ] Портировать проверки и вспомогательные утилиты (`collect-tool-approvals`, `is-approval-needed`, `tool-set`, `tool-error`).
- [ ] Реализовать smooth-stream алгоритм.
- [ ] Настроить генерацию файлов (`generated-file`), reasoning поддержку.

## Блок F. Text Stream / UI stream (`text-stream`, `ui-message-stream`)
- [ ] Портировать `TextStream` helpers (stitching, transformations, `toStreamResponse`).
- [ ] Реализовать `UIMessageStream`, маппинг к структурам UI.
- [ ] Поддержать stop conditions, warnings, reasoning, tool events в потоках.

## Блок G. Tool API (`packages/ai/src/tool`)
- [ ] Перенести объявление tools (`tool`, `dynamicTool`, `tool-set`), approval workflow.
- [ ] Портировать MCP поддержку (`tool/mcp`).
- [ ] Реализовать типовку `ToolDefinition`, `ToolCall`, `ToolResult`.

## Блок H. Registry и модели (`packages/ai/src/registry`, `model`)
- [ ] Портировать `ModelRegistry`, `RegisteredModel`, `ProviderRegistry`.
- [ ] Реализовать `resolveModel`, `resolveEmbeddingModel`, глобальный провайдер (`global.ts`).
- [ ] Настроить механизм `gateway` по умолчанию.

## Блок I. Telemetry & Logging
- [ ] Перенести `telemetry` модуль (Tracer, spans, attributes, recordSpan).
- [ ] Портировать `logger/log-warnings`, общий логгер.
- [ ] Интегрировать с OpenTelemetry (см. блок B).

## Блок J. Дополнительные фичи
- [ ] Портировать `generate-object`, `generate-image`, `generate-speech`, `transcribe`, `embed`.
- [ ] Портировать `agent`, `middleware`, `ui` (по мере необходимости).

## Блок K. Провайдеры (конкретные реализации)
- [ ] OpenAI (Responses API, включая tools, JSON schema, SSE parsing).
- [ ] Anthropic (Claude), Google Generative AI, Groq, xAI, OpenAI-Compatible.
- [ ] Прочие провайдеры из `packages/<provider>` (DeepSeek, Mistral, и т.д.) — определить приоритет/объём.
- [ ] Вспомогательные пакеты (`provider-utils` тесты, фикстуры) использовать как референс.

## Блок L. Тесты
- [ ] Настроить структуру Swift Testing (Targets по блокам).
- [ ] Перенести unit-тесты из `packages/ai/src/**/__tests__` и снапшоты.
- [ ] Перенести тесты из `packages/provider` и `provider-utils` (включая edge/node варианты).
- [ ] Создать моки HTTP/SSE (`URLProtocol`, тестовый SSE генератор).
- [ ] Вести таблицу покрытия (Vitest файл → Swift тесты).

## Блок M. Документация
- [ ] README: добавить базовый пример `AISDK.generateText` и инструкции по установке.
- [ ] Синхронизировать `docs` (Core, Tools, Streams, Providers, Testing).
- [ ] Подготовить генерацию DocC или статичных Markdown.

## Блок N. Управление релизами
- [ ] Оформить `Package.swift` (targets: Core, Provider, ProviderUtils, Tests).
- [ ] Добавить GitHub Actions/CI (swift build/test) — позже.
- [ ] Поддерживать `CHANGELOG.md` и upstream commit в README.

## Блок O. Gateway/OIDC (поздний этап)
- [ ] Интерфейс `GatewayClient`, интеграция с AI Gateway.
- [ ] Адаптер AppAuth и/или `URLSession`-клиент для OIDC.
- [ ] Тесты на refresh/token обмен (моки).
