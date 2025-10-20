# AISDKProvider - File Mapping (TS ↔ Swift)

**Пакет**: `@ai-sdk/provider` → `AISDKProvider`

**Обновлено**: 2025-10-20

---

## Статистика

- **Upstream (TS)**: 114 файлов
- **Swift Port**: 83 файла
- **Покрытие**: 72.8%
- **Статус**: ✅ Базовая реализация завершена

---

## Категории файлов

### 📊 Легенда статусов

| Символ | Значение |
|--------|----------|
| ✅ | Полный паритет (файл портирован, API совпадает) |
| ⚠️ | Частичный паритет (файл есть, но требуется проверка) |
| 🔄 | Объединено с другим файлом |
| ❌ | Отсутствует в Swift порте |
| 📦 | index.ts (не требует порта - Swift использует модули) |

---

## EmbeddingModel (7 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `embedding-model/index.ts` | — | 📦 | Re-export, не требуется |
| 2 | `embedding-model/v2/embedding-model-v2-embedding.ts` | `EmbeddingModel/EmbeddingModelV2Embedding.swift` | ⚠️ | Требуется проверка API |
| 3 | `embedding-model/v2/embedding-model-v2.ts` | `EmbeddingModel/EmbeddingModelV2.swift` | ⚠️ | Требуется проверка API |
| 4 | `embedding-model/v2/index.ts` | — | 📦 | Re-export |
| 5 | `embedding-model/v3/embedding-model-v3-embedding.ts` | `EmbeddingModel/EmbeddingModelV3Embedding.swift` | ⚠️ | Требуется проверка API |
| 6 | `embedding-model/v3/embedding-model-v3.ts` | `EmbeddingModel/EmbeddingModelV3.swift` | ⚠️ | Требуется проверка API |
| 7 | `embedding-model/v3/index.ts` | — | 📦 | Re-export |

**Подитог**: 4/7 файлов портированы (3 index.ts не требуются)

---

## Errors (13 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `errors/ai-sdk-error.ts` | `Errors/AISDKError.swift` | ⚠️ | Проверить структуру ошибки |
| 2 | `errors/api-call-error.ts` | `Errors/APICallError.swift` | ⚠️ | Проверить поля |
| 3 | `errors/empty-response-body-error.ts` | `Errors/EmptyResponseBodyError.swift` | ⚠️ | Проверить |
| 4 | `errors/get-error-message.ts` | `Errors/GetErrorMessage.swift` | ⚠️ | Проверить функцию |
| 5 | `errors/index.ts` | — | 📦 | Re-export |
| 6 | `errors/invalid-argument-error.ts` | `Errors/InvalidArgumentError.swift` | ⚠️ | Проверить |
| 7 | `errors/invalid-prompt-error.ts` | `Errors/InvalidPromptError.swift` | ⚠️ | Проверить |
| 8 | `errors/invalid-response-data-error.ts` | `Errors/InvalidResponseDataError.swift` | ⚠️ | Проверить |
| 9 | `errors/json-parse-error.ts` | `Errors/JSONParseError.swift` | ⚠️ | Проверить |
| 10 | `errors/load-api-key-error.ts` | `Errors/LoadAPIKeyError.swift` | ⚠️ | Проверить |
| 11 | `errors/load-setting-error.ts` | `Errors/LoadSettingError.swift` | ⚠️ | Проверить |
| 12 | `errors/no-content-generated-error.ts` | `Errors/NoContentGeneratedError.swift` | ⚠️ | Проверить |
| 13 | `errors/no-such-model-error.ts` | `Errors/NoSuchModelError.swift` | ⚠️ | Проверить |
| 14 | `errors/too-many-embedding-values-for-call-error.ts` | `Errors/TooManyEmbeddingValuesForCallError.swift` | ⚠️ | Проверить |
| 15 | `errors/type-validation-error.ts` | `Errors/TypeValidationError.swift` | ⚠️ | Проверить |
| 16 | `errors/unsupported-functionality-error.ts` | `Errors/UnsupportedFunctionalityError.swift` | ⚠️ | Проверить |

**Подитог**: 12/13 файлов портированы (1 index.ts не требуется)

---

## ImageModel (8 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `image-model/index.ts` | — | 📦 | Re-export |
| 2 | `image-model/v2/image-model-v2-call-options.ts` | `ImageModel/ImageModelV2CallOptions.swift` | ⚠️ | Проверить опции |
| 3 | `image-model/v2/image-model-v2-call-warning.ts` | `ImageModel/ImageModelV2CallWarning.swift` | ⚠️ | Проверить warnings |
| 4 | `image-model/v2/image-model-v2.ts` | `ImageModel/ImageModelV2.swift` | ⚠️ | Проверить API |
| 5 | `image-model/v2/index.ts` | — | 📦 | Re-export |
| 6 | `image-model/v3/image-model-v3-call-options.ts` | `ImageModel/ImageModelV3CallOptions.swift` | ⚠️ | Проверить опции |
| 7 | `image-model/v3/image-model-v3-call-warning.ts` | `ImageModel/ImageModelV3CallWarning.swift` | ⚠️ | Проверить warnings |
| 8 | `image-model/v3/image-model-v3.ts` | `ImageModel/ImageModelV3.swift` | ⚠️ | Проверить API |
| 9 | `image-model/v3/index.ts` | — | 📦 | Re-export |

**Подитог**: 6/8 файлов портированы (3 index.ts не требуются)

---

## JSONValue (3 файла)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `json-value/index.ts` | — | 📦 | Re-export |
| 2 | `json-value/is-json.ts` | `JSONValue/IsJSON.swift` | ⚠️ | Проверить функции |
| 3 | `json-value/json-value.ts` | `JSONValue/JSONValue.swift` | ⚠️ | Проверить типы |

**Подитог**: 2/3 файла портированы

---

## LanguageModel Middleware (5 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `language-model-middleware/index.ts` | — | 📦 | Re-export |
| 2 | `language-model-middleware/v2/index.ts` | — | 📦 | Re-export |
| 3 | `language-model-middleware/v2/language-model-v2-middleware.ts` | `LanguageModel/Middleware/LanguageModelV2Middleware.swift` | ⚠️ | Проверить middleware API |
| 4 | `language-model-middleware/v3/index.ts` | — | 📦 | Re-export |
| 5 | `language-model-middleware/v3/language-model-v3-middleware.ts` | `LanguageModel/Middleware/LanguageModelV3Middleware.swift` | ⚠️ | Проверить middleware API |

**Подитог**: 2/5 файлов портированы (3 index.ts не требуются)

---

## LanguageModel V2 (18 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `language-model/index.ts` | — | 📦 | Re-export |
| 2 | `language-model/v2/index.ts` | — | 📦 | Re-export |
| 3 | `language-model/v2/language-model-v2-call-options.ts` | `LanguageModel/V2/LanguageModelV2CallOptions.swift` | ⚠️ | Проверить опции |
| 4 | `language-model/v2/language-model-v2-call-warning.ts` | `LanguageModel/V2/LanguageModelV2CallWarning.swift` | ⚠️ | Проверить warnings |
| 5 | `language-model/v2/language-model-v2-content.ts` | `LanguageModel/V2/LanguageModelV2Content.swift` | ⚠️ | Проверить типы контента |
| 6 | `language-model/v2/language-model-v2-data-content.ts` | `LanguageModel/V2/LanguageModelV2DataContent.swift` | ⚠️ | Проверить data content |
| 7 | `language-model/v2/language-model-v2-file.ts` | `LanguageModel/V2/LanguageModelV2File.swift` | ⚠️ | Проверить file types |
| 8 | `language-model/v2/language-model-v2-finish-reason.ts` | `LanguageModel/V2/LanguageModelV2StreamPart.swift` | 🔄 | Объединено в StreamPart |
| 9 | `language-model/v2/language-model-v2-function-tool.ts` | `LanguageModel/V2/LanguageModelV2FunctionTool.swift` | ⚠️ | Проверить tool API |
| 10 | `language-model/v2/language-model-v2-prompt.ts` | `LanguageModel/V2/LanguageModelV2Prompt.swift` | ⚠️ | Проверить prompt types |
| 11 | `language-model/v2/language-model-v2-provider-defined-tool.ts` | `LanguageModel/V2/LanguageModelV2ProviderDefinedTool.swift` | ⚠️ | Проверить |
| 12 | `language-model/v2/language-model-v2-reasoning.ts` | `LanguageModel/V2/LanguageModelV2Reasoning.swift` | ⚠️ | Проверить |
| 13 | `language-model/v2/language-model-v2-response-metadata.ts` | `LanguageModel/V2/LanguageModelV2ResponseMetadata.swift` | ⚠️ | Проверить metadata |
| 14 | `language-model/v2/language-model-v2-source.ts` | `LanguageModel/V2/LanguageModelV2Source.swift` | ⚠️ | Проверить source |
| 15 | `language-model/v2/language-model-v2-stream-part.ts` | `LanguageModel/V2/LanguageModelV2StreamPart.swift` | ⚠️ | Проверить streaming |
| 16 | `language-model/v2/language-model-v2-text.ts` | `LanguageModel/V2/LanguageModelV2Text.swift` | ⚠️ | Проверить text types |
| 17 | `language-model/v2/language-model-v2-tool-call.ts` | `LanguageModel/V2/LanguageModelV2ToolCall.swift` | ⚠️ | Проверить tool calls |
| 18 | `language-model/v2/language-model-v2-tool-choice.ts` | `LanguageModel/V2/LanguageModelV2ToolChoice.swift` | ⚠️ | Проверить tool choice |
| 19 | `language-model/v2/language-model-v2-tool-result.ts` | `LanguageModel/V2/LanguageModelV2ToolResult.swift` | ⚠️ | Проверить tool results |
| 20 | `language-model/v2/language-model-v2-usage.ts` | `LanguageModel/V2/LanguageModelV2StreamPart.swift` | 🔄 | Объединено в StreamPart |
| 21 | `language-model/v2/language-model-v2.ts` | `LanguageModel/V2/LanguageModelV2.swift` | ⚠️ | Проверить главный API |

**Подитог**: 16/18 файлов портированы (2 index.ts, 0 отсутствуют)

**📝 Примечание**: FinishReason и Usage объединены в LanguageModelV2StreamPart.swift

---

## LanguageModel V3 (18 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `language-model/v3/index.ts` | — | 📦 | Re-export |
| 2 | `language-model/v3/language-model-v3-call-options.ts` | `LanguageModel/V3/LanguageModelV3CallOptions.swift` | ⚠️ | Проверить опции |
| 3 | `language-model/v3/language-model-v3-call-warning.ts` | `LanguageModel/V3/LanguageModelV3CallWarning.swift` | ⚠️ | Проверить warnings |
| 4 | `language-model/v3/language-model-v3-content.ts` | `LanguageModel/V3/LanguageModelV3Content.swift` | ⚠️ | Проверить типы контента |
| 5 | `language-model/v3/language-model-v3-data-content.ts` | `LanguageModel/V3/LanguageModelV3DataContent.swift` | ⚠️ | Проверить data content |
| 6 | `language-model/v3/language-model-v3-file.ts` | `LanguageModel/V3/LanguageModelV3File.swift` | ⚠️ | Проверить file types |
| 7 | `language-model/v3/language-model-v3-finish-reason.ts` | `LanguageModel/V3/LanguageModelV3StreamPart.swift` | 🔄 | Объединено в StreamPart |
| 8 | `language-model/v3/language-model-v3-function-tool.ts` | `LanguageModel/V3/LanguageModelV3FunctionTool.swift` | ⚠️ | Проверить tool API |
| 9 | `language-model/v3/language-model-v3-prompt.ts` | `LanguageModel/V3/LanguageModelV3Prompt.swift` | ⚠️ | Проверить prompt types |
| 10 | `language-model/v3/language-model-v3-provider-defined-tool.ts` | `LanguageModel/V3/LanguageModelV3ProviderDefinedTool.swift` | ⚠️ | Проверить |
| 11 | `language-model/v3/language-model-v3-reasoning.ts` | `LanguageModel/V3/LanguageModelV3Reasoning.swift` | ⚠️ | Проверить |
| 12 | `language-model/v3/language-model-v3-response-metadata.ts` | `LanguageModel/V3/LanguageModelV3ResponseMetadata.swift` | ⚠️ | Проверить metadata |
| 13 | `language-model/v3/language-model-v3-source.ts` | `LanguageModel/V3/LanguageModelV3Source.swift` | ⚠️ | Проверить source |
| 14 | `language-model/v3/language-model-v3-stream-part.ts` | `LanguageModel/V3/LanguageModelV3StreamPart.swift` | ⚠️ | Проверить streaming |
| 15 | `language-model/v3/language-model-v3-text.ts` | `LanguageModel/V3/LanguageModelV3Text.swift` | ⚠️ | Проверить text types |
| 16 | `language-model/v3/language-model-v3-tool-call.ts` | `LanguageModel/V3/LanguageModelV3ToolCall.swift` | ⚠️ | Проверить tool calls |
| 17 | `language-model/v3/language-model-v3-tool-choice.ts` | `LanguageModel/V3/LanguageModelV3ToolChoice.swift` | ⚠️ | Проверить tool choice |
| 18 | `language-model/v3/language-model-v3-tool-result.ts` | `LanguageModel/V3/LanguageModelV3ToolResult.swift` | ⚠️ | Проверить tool results |
| 19 | `language-model/v3/language-model-v3-usage.ts` | `LanguageModel/V3/LanguageModelV3StreamPart.swift` | 🔄 | Объединено в StreamPart |
| 20 | `language-model/v3/language-model-v3.ts` | `LanguageModel/V3/LanguageModelV3.swift` | ⚠️ | Проверить главный API |

**Подитог**: 16/18 файлов портированы (1 index.ts, 0 отсутствуют)

**📝 Примечание**: FinishReason и Usage объединены в LanguageModelV3StreamPart.swift

---

## Provider (5 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `provider/index.ts` | — | 📦 | Re-export |
| 2 | `provider/v2/index.ts` | — | 📦 | Re-export |
| 3 | `provider/v2/provider-v2.ts` | `ProviderV2.swift` | ⚠️ | Проверить API |
| 4 | `provider/v3/index.ts` | — | 📦 | Re-export |
| 5 | `provider/v3/provider-v3.ts` | `ProviderV3.swift` | ⚠️ | Проверить API |

**Подитог**: 2/5 файлов портированы (3 index.ts не требуются)

---

## Shared (8 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `shared/index.ts` | — | 📦 | Re-export |
| 2 | `shared/v2/index.ts` | — | 📦 | Re-export |
| 3 | `shared/v2/shared-v2-headers.ts` | `Shared/V2/SharedV2Headers.swift` | ⚠️ | Проверить |
| 4 | `shared/v2/shared-v2-provider-metadata.ts` | `Shared/V2/SharedV2ProviderMetadata.swift` | ⚠️ | Проверить |
| 5 | `shared/v2/shared-v2-provider-options.ts` | `Shared/V2/SharedV2ProviderOptions.swift` | ⚠️ | Проверить |
| 6 | `shared/v3/index.ts` | — | 📦 | Re-export |
| 7 | `shared/v3/shared-v3-headers.ts` | `Shared/V3/SharedV3Headers.swift` | ⚠️ | Проверить |
| 8 | `shared/v3/shared-v3-provider-metadata.ts` | `Shared/V3/SharedV3ProviderMetadata.swift` | ⚠️ | Проверить |
| 9 | `shared/v3/shared-v3-provider-options.ts` | `Shared/V3/SharedV3ProviderOptions.swift` | ⚠️ | Проверить |

**Подитог**: 6/8 файлов портированы (3 index.ts не требуются)

---

## SpeechModel (8 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `speech-model/index.ts` | — | 📦 | Re-export |
| 2 | `speech-model/v2/index.ts` | — | 📦 | Re-export |
| 3 | `speech-model/v2/speech-model-v2-call-options.ts` | `SpeechModel/SpeechModelV2CallOptions.swift` | ⚠️ | Проверить |
| 4 | `speech-model/v2/speech-model-v2-call-warning.ts` | `SpeechModel/SpeechModelV2CallWarning.swift` | ⚠️ | Проверить |
| 5 | `speech-model/v2/speech-model-v2.ts` | `SpeechModel/SpeechModelV2.swift` | ⚠️ | Проверить API |
| 6 | `speech-model/v3/index.ts` | — | 📦 | Re-export |
| 7 | `speech-model/v3/speech-model-v3-call-options.ts` | `SpeechModel/SpeechModelV3CallOptions.swift` | ⚠️ | Проверить |
| 8 | `speech-model/v3/speech-model-v3-call-warning.ts` | `SpeechModel/SpeechModelV3CallWarning.swift` | ⚠️ | Проверить |
| 9 | `speech-model/v3/speech-model-v3.ts` | `SpeechModel/SpeechModelV3.swift` | ⚠️ | Проверить API |

**Подитог**: 6/8 файлов портированы (3 index.ts не требуются)

---

## TranscriptionModel (8 файлов)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `transcription-model/index.ts` | — | 📦 | Re-export |
| 2 | `transcription-model/v2/index.ts` | — | 📦 | Re-export |
| 3 | `transcription-model/v2/transcription-model-v2-call-options.ts` | `TranscriptionModel/TranscriptionModelV2CallOptions.swift` | ⚠️ | Проверить |
| 4 | `transcription-model/v2/transcription-model-v2-call-warning.ts` | `TranscriptionModel/TranscriptionModelV2CallWarning.swift` | ⚠️ | Проверить |
| 5 | `transcription-model/v2/transcription-model-v2.ts` | `TranscriptionModel/TranscriptionModelV2.swift` | ⚠️ | Проверить API |
| 6 | `transcription-model/v3/index.ts` | — | 📦 | Re-export |
| 7 | `transcription-model/v3/transcription-model-v3-call-options.ts` | `TranscriptionModel/TranscriptionModelV3CallOptions.swift` | ⚠️ | Проверить |
| 8 | `transcription-model/v3/transcription-model-v3-call-warning.ts` | `TranscriptionModel/TranscriptionModelV3CallWarning.swift` | ⚠️ | Проверить |
| 9 | `transcription-model/v3/transcription-model-v3.ts` | `TranscriptionModel/TranscriptionModelV3.swift` | ⚠️ | Проверить API |

**Подитог**: 6/8 файлов портированы (3 index.ts не требуются)

---

## Root файлы (1 файл)

| # | TypeScript | Swift | Статус | Примечания |
|---|------------|-------|--------|------------|
| 1 | `src/index.ts` | — | 📦 | Main re-export |

**Подитог**: 0/1 файл (index.ts не требуется)

---

## 📊 Итоговая статистика

### По категориям

| Категория | TS файлов | Swift файлов | index.ts | Отсутствует | Покрытие |
|-----------|-----------|--------------|----------|-------------|----------|
| EmbeddingModel | 7 | 4 | 3 | 0 | 100% |
| Errors | 13 | 12 | 1 | 0 | 100% |
| ImageModel | 8 | 6 | 3 | 0 | 100% |
| JSONValue | 3 | 2 | 1 | 0 | 100% |
| LM Middleware | 5 | 2 | 3 | 0 | 100% |
| LanguageModel V2 | 18 | 16 | 2 | 0 | 100% ✅ |
| LanguageModel V3 | 18 | 16 | 1 | 0 | 100% ✅ |
| Provider | 5 | 2 | 3 | 0 | 100% |
| Shared | 8 | 6 | 3 | 0 | 100% |
| SpeechModel | 8 | 6 | 3 | 0 | 100% |
| TranscriptionModel | 8 | 6 | 3 | 0 | 100% |
| Root | 1 | 0 | 1 | 0 | — |

### Общий итог

- **Всего TS файлов**: 114
- **index.ts файлов** (не требуют порта): 27
- **Реальных TS файлов**: 87
- **Swift файлов**: 83
- **Объединенных типов**: 4 (FinishReason, Usage в StreamPart файлах)
- **Отсутствующих**: 0
- **Покрытие**: **100%** (87/87 учитывая объединения)

---

## ✅ Результаты проверки

### 1. FinishReason и Usage типы - НАЙДЕНЫ ✅

**Статус**: Типы не отсутствуют, а объединены в StreamPart файлы

**V2**:
- `LanguageModelV2FinishReason` → определен в `LanguageModelV2StreamPart.swift`
- `LanguageModelV2Usage` → определен в `LanguageModelV2StreamPart.swift`

**V3**:
- `LanguageModelV3FinishReason` → определен в `LanguageModelV3StreamPart.swift`
- `LanguageModelV3Usage` → определен в `LanguageModelV3StreamPart.swift`

**Вывод**: Swift порт использует стратегию объединения связанных типов в один файл вместо разделения на отдельные файлы. Это валидный подход для Swift и не является проблемой паритета.

---

## 🔍 Архитектурные различия

### Организация файлов

**TypeScript (upstream)**:
- Один тип = один файл
- `language-model-v2-finish-reason.ts` содержит только FinishReason
- `language-model-v2-usage.ts` содержит только Usage

**Swift (наш порт)**:
- Связанные типы объединены логически
- `LanguageModelV2StreamPart.swift` содержит:
  - `LanguageModelV2StreamPart` enum
  - `LanguageModelV2FinishReason` enum
  - `LanguageModelV2Usage` struct

**Обоснование**: В Swift это более идиоматично - держать тесно связанные типы вместе, особенно если они используются только в контексте друг друга.

---

## Следующие шаги

1. ✅ Создан полный mapping
2. 🔄 **СЛЕДУЮЩЕЕ**: Проверить наличие FinishReason и Usage в существующих файлах
3. ⏳ Если отсутствуют - создать эти типы
4. ⏳ Начать детальное API сравнение для каждого файла
5. ⏳ Создать api-parity.md с построчным сравнением

---

**Примечание**: Все файлы с ⚠️ требуют детальной проверки API в следующей фазе.
