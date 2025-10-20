# AISDKProviderUtils - File Mapping (TS ↔ Swift)

**Пакет**: `@ai-sdk/provider-utils` → `AISDKProviderUtils` + `AISDKZodAdapter`

**Обновлено**: 2025-10-20

---

## Статистика

- **Upstream (TS)**: 100 файлов
- **Swift Port**: 49 файлов (AISDKProviderUtils) + 11 файлов (AISDKZodAdapter) = **60 файлов**
- **Покрытие**: 60%
- **Статус**: ⚠️ Требуется детальная проверка

**Важное примечание**: Swift порт разделен на 2 target'а:
1. `AISDKProviderUtils` - основные утилиты и типы
2. `AISDKZodAdapter` - вся Zod/Schema логика (отдельный модуль)

---

## Категории файлов

### 📊 Легенда статусов

| Символ | Значение |
|--------|----------|
| ✅ | Полный паритет (файл портирован, API совпадает) |
| ⚠️ | Частичный паритет (файл есть, но требуется проверка) |
| 🔄 | Объединено с другим файлом |
| ❌ | Отсутствует в Swift порте |
| 📦 | index.ts (не требует порта) |
| 🧪 | Тестовый файл (.test-d.ts) |
| 🎯 | Вынесено в отдельный target (AISDKZodAdapter) |

---

## Основные утилиты (26 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `combine-headers.ts` | `CombineHeaders.swift` | ⚠️ | Проверить API |
| 2 | `convert-async-iterator-to-readable-stream.ts` | `ConvertAsyncIteratorToReadableStream.swift` | ⚠️ | Проверить |
| 3 | `delay.ts` | `Delay.swift` | ⚠️ | Проверить |
| 4 | `extract-response-headers.ts` | `ExtractResponseHeaders.swift` | ⚠️ | Проверить |
| 5 | `fetch-function.ts` | `FetchFunction.swift` | ⚠️ | Проверить |
| 6 | `generate-id.ts` | `GenerateID.swift` | ⚠️ | Проверить |
| 7 | `get-error-message.ts` | `GetErrorMessage.swift` | ⚠️ | Проверить |
| 8 | `get-from-api.ts` | `GetFromAPI.swift` | ⚠️ | Проверить |
| 9 | `get-runtime-environment-user-agent.ts` | `GetRuntimeEnvironmentUserAgent.swift` | ⚠️ | Проверить |
| 10 | `handle-fetch-error.ts` | `HandleFetchError.swift` | ⚠️ | Проверить |
| 11 | `index.ts` | — | 📦 | Re-export |
| 12 | `inject-json-instruction.ts` | ❌ | ❌ | **ОТСУТСТВУЕТ** |
| 13 | `is-abort-error.ts` | `IsAbortError.swift` | ⚠️ | Проверить |
| 14 | `is-async-iterable.ts` | `IsAsyncIterable.swift` | ⚠️ | Проверить |
| 15 | `is-url-supported.ts` | `IsUrlSupported.swift` | ⚠️ | Проверить |
| 16 | `load-api-key.ts` | `LoadAPIKey.swift` | ⚠️ | Проверить |
| 17 | `load-optional-setting.ts` | `LoadOptionalSetting.swift` | ⚠️ | Проверить |
| 18 | `load-setting.ts` | `LoadSetting.swift` | ⚠️ | Проверить |
| 19 | `media-type-to-extension.ts` | `MediaTypeToExtension.swift` | ⚠️ | Проверить |
| 20 | `parse-json-event-stream.ts` | `ParseJsonEventStream.swift` | ⚠️ | Проверить |
| 21 | `parse-json.ts` | `ParseJSON.swift` | ⚠️ | Проверить |
| 22 | `parse-provider-options.ts` | `ParseProviderOptions.swift` | ⚠️ | Проверить |
| 23 | `post-to-api.ts` | `PostToAPI.swift` | ⚠️ | Проверить |
| 24 | `provider-defined-tool-factory.ts` | `ProviderDefinedToolFactory.swift` | ⚠️ | Проверить |
| 25 | `remove-undefined-entries.ts` | `RemoveUndefinedEntries.swift` | ⚠️ | Проверить |
| 26 | `resolve.ts` | `Resolve.swift` | ⚠️ | Проверить |
| 27 | `response-handler.ts` | `ResponseHandler.swift` | ⚠️ | Проверить |
| 28 | `schema.test-d.ts` | — | 🧪 | Type test file |
| 29 | `schema.ts` | `Schema/Schema.swift` | ⚠️ | Проверить |
| 30 | `secure-json-parse.ts` | `SecureJsonParse.swift` | ⚠️ | Проверить |
| 31 | `uint8-utils.ts` | `Uint8Utils.swift` | ⚠️ | Проверить |
| 32 | `validate-types.ts` | `ValidateTypes.swift` | ⚠️ | Проверить |
| 33 | `version.ts` | `Version.swift` | ⚠️ | Проверить |
| 34 | `with-user-agent-suffix.ts` | `WithUserAgentSuffix.swift` | ⚠️ | Проверить |
| 35 | `without-trailing-slash.ts` | `WithoutTrailingSlash.swift` | ⚠️ | Проверить |

**Подитог**: 24/26 портированы (1 index.ts, 1 test-d.ts, 1 отсутствует)

**Отсутствующие**:
- ❌ `inject-json-instruction.ts`

---

## Types (15 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `types/index.ts` | — | 📦 | Re-export |
| 2 | `types/assistant-model-message.ts` | `ModelMessage.swift` | 🔄 | Объединено |
| 3 | `types/content-part.ts` | `ContentPart.swift` | ⚠️ | Проверить |
| 4 | `types/data-content.ts` | `DataContent.swift` | ⚠️ | Проверить |
| 5 | `types/execute-tool.ts` | `ExecuteTool.swift` | ⚠️ | Проверить |
| 6 | `types/model-message.ts` | `ModelMessage.swift` | 🔄 | Объединено |
| 7 | `types/provider-options.ts` | ❌ | ❌ | **ОТСУТСТВУЕТ** или объединено |
| 8 | `types/system-model-message.ts` | `ModelMessage.swift` | 🔄 | Объединено |
| 9 | `types/tool-approval-request.ts` | `Tool.swift` | 🔄 | Объединено в Tool |
| 10 | `types/tool-approval-response.ts` | `Tool.swift` | 🔄 | Объединено в Tool |
| 11 | `types/tool-call.ts` | `Tool.swift` | 🔄 | Объединено в Tool |
| 12 | `types/tool-model-message.ts` | `ModelMessage.swift` | 🔄 | Объединено |
| 13 | `types/tool-result.ts` | `Tool.swift` | 🔄 | Объединено в Tool |
| 14 | `types/tool.test-d.ts` | — | 🧪 | Type test |
| 15 | `types/tool.ts` | `Tool.swift` | ⚠️ | Проверить |
| 16 | `types/user-model-message.ts` | `ModelMessage.swift` | 🔄 | Объединено |

**Подитог**: 13/15 портированы (2 index/test, 1 возможно отсутствует)

**Архитектурное решение**:
- Swift объединяет related message types в `ModelMessage.swift`
- Tool-related типы объединены в `Tool.swift`

**Требует проверки**:
- ❌ `types/provider-options.ts` - возможно в ParseProviderOptions.swift

---

## Test utilities (8 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `test/index.ts` | `TestSupport/TestSupportIndex.swift` | ⚠️ | Проверить |
| 2 | `test/convert-array-to-async-iterable.ts` | `TestSupport/ConvertArrayToAsyncIterable.swift` | ⚠️ | Проверить |
| 3 | `test/convert-array-to-readable-stream.ts` | `TestSupport/ConvertArrayToReadableStream.swift` | ⚠️ | Проверить |
| 4 | `test/convert-async-iterable-to-array.ts` | `TestSupport/ConvertAsyncIterableToArray.swift` | ⚠️ | Проверить |
| 5 | `test/convert-readable-stream-to-array.ts` | `TestSupport/ConvertReadableStreamToArray.swift` | ⚠️ | Проверить |
| 6 | `test/convert-response-stream-to-array.ts` | `TestSupport/ConvertResponseStreamToArray.swift` | ⚠️ | Проверить |
| 7 | `test/is-node-version.ts` | ❌ | ❌ | **ОТСУТСТВУЕТ** (Node-specific) |
| 8 | `test/mock-id.ts` | ❌ | ❌ | **ОТСУТСТВУЕТ** |

**Подитог**: 6/8 портированы

**Отсутствующие**:
- ❌ `test/is-node-version.ts` - Node.js специфичный, не нужен в Swift
- ❌ `test/mock-id.ts` - требуется проверка

---

## Schema: Zod3 to JSON Schema (52 файла) → AISDKZodAdapter target

### Основные файлы (5 файлов)

| # | TypeScript | Swift (AISDKZodAdapter) | Статус | Примечания |
|---|------------|-------------------------|--------|------------|
| 1 | `to-json-schema/arktype-to-json-schema.ts` | `ArkTypeToJSONSchema.swift` | 🎯 | Отдельный target |
| 2 | `to-json-schema/effect-to-json-schema.ts` | `EffectToJSONSchema.swift` | 🎯 | Отдельный target |
| 3 | `to-json-schema/valibot-to-json-schema.ts` | `ValibotToJSONSchema.swift` | 🎯 | Отдельный target |
| 4 | `to-json-schema/zod3-to-json-schema/index.ts` | — | 📦 | Re-export |
| 5 | `to-json-schema/zod3-to-json-schema/get-relative-path.ts` | `Zod3/Zod3ParseDef.swift` | 🔄 | Объединено |

**Подитог**: 4/5 портированы (1 index.ts)

---

### Zod3 Core (5 файлов)

| # | TypeScript | Swift (AISDKZodAdapter) | Статус | Примечания |
|---|------------|-------------------------|--------|------------|
| 1 | `zod3-to-json-schema/options.ts` | `Zod3/Zod3Options.swift` | 🎯 | Отдельный target |
| 2 | `zod3-to-json-schema/parse-def.ts` | `Zod3/Zod3ParseDef.swift` | 🎯 | Отдельный target |
| 3 | `zod3-to-json-schema/parse-types.ts` | `Zod3/Zod3ParseDef.swift` | 🔄 | Объединено в ParseDef |
| 4 | `zod3-to-json-schema/refs.ts` | `Zod3/Zod3ParseDef.swift` | 🔄 | Объединено в ParseDef |
| 5 | `zod3-to-json-schema/select-parser.ts` | `Zod3/Zod3ParseDef.swift` | 🔄 | Объединено в ParseDef |
| 6 | `zod3-to-json-schema/zod3-to-json-schema.ts` | `Zod3/Zod3ToJSONSchema.swift` | 🎯 | Отдельный target |

**Подитог**: 6/6 портированы (4 объединены в ParseDef)

---

### Zod3 Parsers (27 файлов → 1 файл)

**TypeScript**: 27 отдельных файлов parsers/*
**Swift**: `Zod3/Zod3Parsers.swift` (1217 строк)

| # | TypeScript | Swift | Статус |
|---|------------|-------|--------|
| 1 | `parsers/any.ts` | `Zod3Parsers.swift` | 🔄 |
| 2 | `parsers/array.ts` | `Zod3Parsers.swift` | 🔄 |
| 3 | `parsers/bigint.ts` | `Zod3Parsers.swift` | 🔄 |
| 4 | `parsers/boolean.ts` | `Zod3Parsers.swift` | 🔄 |
| 5 | `parsers/branded.ts` | `Zod3Parsers.swift` | 🔄 |
| 6 | `parsers/catch.ts` | `Zod3Parsers.swift` | 🔄 |
| 7 | `parsers/date.ts` | `Zod3Parsers.swift` | 🔄 |
| 8 | `parsers/default.ts` | `Zod3Parsers.swift` | 🔄 |
| 9 | `parsers/effects.ts` | `Zod3Parsers.swift` | 🔄 |
| 10 | `parsers/enum.ts` | `Zod3Parsers.swift` | 🔄 |
| 11 | `parsers/intersection.ts` | `Zod3Parsers.swift` | 🔄 |
| 12 | `parsers/literal.ts` | `Zod3Parsers.swift` | 🔄 |
| 13 | `parsers/map.ts` | `Zod3Parsers.swift` | 🔄 |
| 14 | `parsers/native-enum.ts` | `Zod3Parsers.swift` | 🔄 |
| 15 | `parsers/never.ts` | `Zod3Parsers.swift` | 🔄 |
| 16 | `parsers/null.ts` | `Zod3Parsers.swift` | 🔄 |
| 17 | `parsers/nullable.ts` | `Zod3Parsers.swift` | 🔄 |
| 18 | `parsers/number.ts` | `Zod3Parsers.swift` | 🔄 |
| 19 | `parsers/object.ts` | `Zod3Parsers.swift` | 🔄 |
| 20 | `parsers/optional.ts` | `Zod3Parsers.swift` | 🔄 |
| 21 | `parsers/pipeline.ts` | `Zod3Parsers.swift` | 🔄 |
| 22 | `parsers/promise.ts` | `Zod3Parsers.swift` | 🔄 |
| 23 | `parsers/readonly.ts` | `Zod3Parsers.swift` | 🔄 |
| 24 | `parsers/record.ts` | `Zod3Parsers.swift` | 🔄 |
| 25 | `parsers/set.ts` | `Zod3Parsers.swift` | 🔄 |
| 26 | `parsers/string.ts` | `Zod3Parsers.swift` | 🔄 |
| 27 | `parsers/tuple.ts` | `Zod3Parsers.swift` | 🔄 |
| 28 | `parsers/undefined.ts` | `Zod3Parsers.swift` | 🔄 |
| 29 | `parsers/union.ts` | `Zod3Parsers.swift` | 🔄 |
| 30 | `parsers/unknown.ts` | `Zod3Parsers.swift` | 🔄 |

**Подитог**: 27/27 портированы (все объединены в один файл)

**Архитектурное решение**: В Swift все parsers объединены в один файл `Zod3Parsers.swift` (1217 строк). Это более идиоматично для Swift и упрощает поддержку.

---

## Дополнительные Swift файлы (не в upstream)

| # | Swift | Описание |
|---|-------|----------|
| 1 | `JSONValue/JSONValueToFoundation.swift` | Конверсия JSONValue → Foundation types |
| 2 | `MultipartFormDataBuilder.swift` | Построение multipart form data |
| 3 | `ProviderHTTPResponse.swift` | HTTP response wrapper |
| 4 | `Schema/JSONSchemaValidator.swift` | JSON Schema валидация |
| 5 | `SplitDataUrl.swift` | Парсинг data URLs |

**Статус**: Дополнительные утилиты, не имеющие прямого upstream эквивалента

---

## AISDKZodAdapter - Дополнительные файлы

| # | Swift | Описание |
|---|-------|----------|
| 1 | `JSONValueCompat.swift` | Совместимость JSONValue |
| 2 | `PublicBuilders.swift` | Public API для schema builders |
| 3 | `ZLikeDSL.swift` | Zod-подобный DSL для Swift |
| 4 | `Zod3/Zod3Types.swift` | Core Zod типы |

---

## 📊 Итоговая статистика

### По категориям

| Категория | TS файлов | Swift файлов | Покрытие | Примечания |
|-----------|-----------|--------------|----------|------------|
| Основные утилиты | 26 | 24 | 92.3% | 1 отсутствует |
| Types | 15 | 4 | 93.3% | Объединены логически |
| Test utilities | 8 | 6 | 75% | 2 отсутствует (Node-specific) |
| Schema: Основные | 5 | 4 | 80% | В AISDKZodAdapter |
| Schema: Zod3 Core | 6 | 2 | 100% | Объединены |
| Schema: Parsers | 27 | 1 | 100% | Все в Zod3Parsers.swift |
| Index файлы | 2 | 0 | — | Не требуются |
| Test-d файлы | 2 | 0 | — | Type tests |

### Общий итог

- **Всего TS файлов**: 100
- **Index.ts файлов**: 2
- **Test-d.ts файлов**: 2
- **Реальных TS файлов**: 96
- **Swift файлов**: 49 (AISDKProviderUtils) + 11 (AISDKZodAdapter) = **60**
- **Отсутствующих**: ~5-6 файлов
- **Покрытие**: **~94%** (с учетом объединений и архитектурных решений)

---

## 🚨 Отсутствующие файлы

### Критические

_Пока не найдено критических отсутствий_

### Высокий приоритет

1. **inject-json-instruction.ts**
   - Требуется проверка использования
   - Возможно объединен с другими функциями

2. **types/provider-options.ts**
   - Возможно в ParseProviderOptions.swift
   - Требуется API проверка

### Низкий приоритет

1. **test/is-node-version.ts**
   - Node.js специфичный
   - Не применим к Swift
   - **Статус**: WONTFIX

2. **test/mock-id.ts**
   - Тестовая утилита
   - Возможно реализована иначе
   - Требуется проверка

---

## 🔍 Архитектурные решения

### 1. Разделение на два target'а

**Upstream (TypeScript)**:
- Один пакет `@ai-sdk/provider-utils`
- Все вместе: утилиты + типы + schema

**Swift (наш порт)**:
- `AISDKProviderUtils` - утилиты и типы
- `AISDKZodAdapter` - вся schema/zod логика

**Обоснование**: Модульная архитектура, возможность использовать Zod независимо

---

### 2. Объединение Zod parsers

**Upstream**: 27 отдельных файлов parsers/*.ts

**Swift**: 1 файл `Zod3Parsers.swift` (1217 строк)

**Обоснование**: Все parsers тесно связаны, проще поддержка в одном файле

---

### 3. Объединение types

**Upstream**:
- `assistant-model-message.ts`
- `system-model-message.ts`
- `tool-model-message.ts`
- `user-model-message.ts`

**Swift**: `ModelMessage.swift` (объединяет все типы сообщений)

**Обоснование**: Логическая группировка, enum с associated values

---

## Следующие шаги

1. ✅ Создан полный mapping
2. 🔄 **СЛЕДУЮЩЕЕ**: Проверить отсутствующие файлы
   - inject-json-instruction.ts
   - types/provider-options.ts
   - test/mock-id.ts
3. ⏳ API comparison для каждого файла
4. ⏳ Проверить дополнительные Swift файлы (зачем добавлены)
5. ⏳ Создать api-parity.md

---

**Примечание**: AISDKZodAdapter - это не внешняя зависимость, а часть того же Swift пакета (отдельный target для модульности).
