# Структура Swift-пакета (зеркало Vercel AI SDK)

Цель: повторить структуру `packages/ai/src` с минимальными отклонениями, адаптируя только под особенности Swift/SwiftPM.

## Core (Sources/SwiftAISDK/Core)
- generate-text → `GenerateText`, `GenerateTextResult`
- stream-text → `StreamText`, `StreamTextResult`
- text-stream → `TextStream`
- ui-message-stream → `UIMessageStream`
- prompt → `StandardizePrompt`
- tool → `ToolDefinition`, `ToolCall`, MCP
- registry → `ModelRegistry`, `ProviderRegistry`
- model → `ResolveModel`, adapters V2→V3
- error → `AIError`, `UnsupportedModelVersionError`
- telemetry → `TelemetryTracer`
- util → вспомогательные функции (мердж контента, генераторы ID)
- logger → `AILogger`

## Providers (Sources/SwiftAISDK/Providers)
- provider base (аналог `@ai-sdk/provider`): `LanguageModelV2`, `LanguageModelV3`, `EmbeddingModel`, `ToolChoice`, `Usage`
- provider-utils: HTTP helpers, SSE parser, schema utils
- OpenAI, Anthropic, Google, Groq, xAI … — структура папок повторяет `packages/<provider>`
- `Gateway` — модуль, интерфейс заложен, реализация позже

## Shared (Sources/SwiftAISDK/Shared)
- Общие типы (ID, массивы контента, Markdown разбор, Base64 утилиты)

## Tests
- Структура каталогов повторяет plan/tests: CoreTests, StreamsTests, ToolsTests, ProvidersTests.

## External/Docs
- README и примеры — отдельные таргеты, но содержание повторяет основную документацию (`docs/Core.md` и т.п.)
