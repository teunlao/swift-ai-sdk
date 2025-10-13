# Принципы портирования

## Архитектура пакетов

**Swift AI SDK организован в 3 отдельных SwiftPM пакета**, повторяя upstream структуру `@ai-sdk`:

### Граф зависимостей
```
AISDKProvider (no deps)
    ↑
AISDKProviderUtils (depends on: AISDKProvider)
    ↑
SwiftAISDK (depends on: AISDKProvider, AISDKProviderUtils, EventSourceParser)
```

### Соответствие с upstream
| Swift Package | TypeScript Package | Назначение |
|---------------|-------------------|-----------|
| `AISDKProvider` | `@ai-sdk/provider` | Foundation types, protocols, errors |
| `AISDKProviderUtils` | `@ai-sdk/provider-utils` | HTTP, JSON, schema, tools utilities |
| `SwiftAISDK` | `@ai-sdk/ai` | High-level SDK (generateText, streams, middleware) |

### Правила размещения кода
- **AISDKProvider**: типы протоколов (LanguageModel, EmbeddingModel, etc.), provider errors, JSONValue, middleware interfaces
- **AISDKProviderUtils**: utilities (HTTP client, JSON parsing, schema validation, tool definitions, delays, ID generation)
- **SwiftAISDK**: SDK functionality (generateText, prompt conversion, registry, telemetry, MCP integration)

### Импорты
- **AISDKProvider**: не импортирует другие пакеты (foundation)
- **AISDKProviderUtils**: `import AISDKProvider`
- **SwiftAISDK**: `import AISDKProvider` + `import AISDKProviderUtils`

### Дубликаты функций (intentional)
`getErrorMessage()` экспортируется из **обоих** AISDKProvider и AISDKProviderUtils (matches upstream):
- **AISDKProvider**: для internal error messages в provider types
- **AISDKProviderUtils**: для utility functions
- **SwiftAISDK**: использует qualified calls `AISDKProvider.getErrorMessage()` (matches upstream `@ai-sdk/ai` importing from `@ai-sdk/provider`)

## Паритет с Vercel AI SDK

1. **Полный паритет с Vercel AI SDK.**
- API (сигнатуры, структура параметров, названия типов) повторяем 1:1, учитывая особенности Swift.
- Поведение на уровне запросов: заголовки, параметры, форматы тела, порядок шагов — полностью совпадает с TypeScript-версией.
- Параметры, которые в оригинале поддерживаются/отклоняются, ведут себя аналогично.
- Исторические слои (`LanguageModelV2` → `LanguageModelV3`) сохраняем и реализуем так же, как в исходном коде (через прокси-адаптер).
- Прогресс фиксируем построчно: по каждому файлу отмечаем и реализацию, и перенос тестов (Vitest → Swift Testing) либо принятое решение по покрытию.

2. **Обработка ошибок.**
   - Соответствие типам ошибок Vercel (мэппинг на Swift-error enum'ы).
   - Полная симметрия по сообщениям, кодам и структурам метаданных.
   - Внутренние диагностические поля (warnings, usage, providerMetadata) повторяются.

3. **Инструменты (Tools).**
   - Структура tool definition, вызовы, serialization input/output — без упрощений.
   - MCP и прочие расширения охватываются так же, как в TypeScript-версии.

4. **Заголовки и запросы.**
   - Каждый заголовок/атрибут/квери-параметр, формируемый в TS, должен быть сформирован в Swift.
   - Хранить таблицу соответствий (файл `plan/http-mapping.md`) — проверка актуальности.

5. **Ответы провайдера.**
   - Парсинг, обработка stream частей, ошибок, finishReason, usage — зеркально оригиналу.
   - Исправления/обходы багов накладываются только если они есть в исходнике.

6. **Документация.**
   - README, описания типов, комментарии — отражают текущую реализацию, не оставляя расхождений.

7. **Тесты.**
   - Любой тестовый сценарий в TypeScript должен иметь аналог в Swift.

## Контроль изменений
- Перед внедрением новой функции сравниваем с TypeScript-версией (в `external/`).
- Изменение логики без основания из оригинала запрещено.
- Все дизайн-решения фиксируем в `plan/design-decisions.md`.
