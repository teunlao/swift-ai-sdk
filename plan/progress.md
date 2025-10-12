# Прогресс портирования

> Этот файл отражает текущий статус портирования. Детальные описания архивируются после завершения блоков.
> Пометки агентов: [executor], [validator]

Формат: отмечаем завершённые элементы из `plan/todo.md`, указываем дату/комментарий.

## Сводка (Last Update: 2025-10-12)
- ✅ **EventSourceParser**: 100% паритет, 30 тестов
- ✅ **LanguageModelV2**: 17 типов, **50 тестов** (+14 новых), **100% покрытие** типов ✅
- ✅ **LanguageModelV3**: 17 типов, 39 тестов, 100% паритет (+ preliminary field)
- ✅ **Provider Errors**: 15 типов, 26 тестов, 100% паритет
- ✅ **JSONValue**: Codable + Expressible протоколы
- 📊 **Итого**: ~5200+ строк кода, 69 файлов, **145/145 тестов** ✅ 🎯
- 🏗️ **Сборка**: `swift build` ~0.2-1.2s, `swift test` **145/145 passed**

## Блок A. Инфраструктура (`@ai-sdk/provider`)
- [x] **shared типы** — JSONValue (Codable + Expressible), SharedV2/V3 алиасы ✅
  - `Sources/SwiftAISDK/Provider/JSONValue/`, `Sources/SwiftAISDK/Provider/Shared/V{2,3}/`
- [x] **language-model/v2** — 17 типов (Content, Tools, Stream, Metadata) ✅
  - `Sources/SwiftAISDK/Provider/LanguageModel/V2/*.swift` (17 файлов)
  - 36 тестов, 100% паритет
- [x] **language-model/v3** — 17 типов (+ preliminary field в ToolResult) ✅
  - `Sources/SwiftAISDK/Provider/LanguageModel/V3/*.swift` (17 файлов)
  - 39 тестов, 100% паритет
  - 📋 Анализ: `plan/v2-vs-v3-analysis.md`
- [x] **errors** — 15 типов (APICallError, ValidationError, etc) ✅
  - `Sources/SwiftAISDK/Provider/Errors/*.swift` (15 файлов)
  - 26 тестов, 100% паритет
- [ ] provider registry — не начато
- [ ] экспорт API — не начато
- [ ] embedding/speech/image/transcription модели — не начато

## Блок B. Provider-utils
- [x] **SSE parser** — EventSourceParser (порт `eventsource-parser@3.0.6`) ✅
  - `Sources/EventSourceParser/*.swift` (3 файла)
  - 30 тестов, 100% паритет
  - 📋 Ревью: `plan/review-2025-10-12-parser.md`
- [ ] generate-id / createIdGenerator — не начато
- [ ] HTTP-хелперы (fetch/post/retry) — не начато
- [ ] load-setting — не начато
- [ ] schema/validation — не начато
- [ ] runtime user agent — не начато

## Блок C. Util (packages/ai/src/util)
- [ ] асинхронные стримы
- [ ] retry/error utils
- [ ] Data URL/media type
- [ ] JSON helpers
- [ ] array/object helpers

## Блок D. Prompt
- [ ] структуры сообщений
- [ ] standardizePrompt
- [ ] prepare-call-settings
- [ ] convert-to-language-model-prompt
- [ ] обработка ошибок
- [ ] wrap-gateway-error

## Блок E. Generate/Stream Text
- [ ] структуры результата
- [ ] generateText основа
- [ ] streamText основа
- [ ] tool вызовы
- [ ] smooth stream
- [ ] reasoning/файлы
### Перечень по файлам (generate-text)
- [ ] packages/ai/src/generate-text/generate-text.ts → Swift `Core/GenerateText/GenerateText.swift`
- [ ] packages/ai/src/generate-text/stream-text.ts → Swift `Core/GenerateText/StreamText.swift`
- [ ] packages/ai/src/generate-text/stream-text-result.ts → Swift `Core/GenerateText/StreamTextResult.swift`
- [ ] packages/ai/src/generate-text/generate-text-result.ts → Swift `Core/GenerateText/GenerateTextResult.swift`
- [ ] packages/ai/src/generate-text/step-result.ts → Swift `Core/GenerateText/StepResult.swift`
- [ ] packages/ai/src/generate-text/smooth-stream.ts → Swift `Core/GenerateText/SmoothStream.swift`
- [ ] packages/ai/src/generate-text/execute-tool-call.ts → Swift `Core/Tools/ExecuteToolCall.swift`
- [ ] packages/ai/src/generate-text/parse-tool-call.ts → Swift `Core/Tools/ParseToolCall.swift`
- [ ] packages/ai/src/generate-text/collect-tool-approvals.ts → Swift `Core/Tools/CollectToolApprovals.swift`

## Блок F. Text/UI stream
- [ ] TextStream helpers
- [ ] UIMessageStream
- [ ] stop conditions/warnings

## Блок G. Tool API
- [ ] tool/dynamicTool
- [ ] tool-set
- [ ] MCP

## Блок H. Registry/Model
- [-] **resolveModel** — заглушка без логики адаптера V2→V3 ⚠️
  - Файл: `Sources/SwiftAISDK/Core/Model/ResolveModel.swift`
- [ ] ModelRegistry — не начато
- [ ] global provider — не начато

## Блок I. Telemetry/Logging
- [ ] telemetry
- [ ] log-warnings

## Блок J. Дополнительные фичи
- [ ] generate-object
- [ ] generate-image
- [ ] generate-speech
- [ ] transcribe
- [ ] embed
- [ ] agent/middleware/ui (при необходимости)

## Блок K. Провайдеры
- [ ] OpenAI
- [ ] OpenAI-compatible
- [ ] Anthropic
- [ ] Google
- [ ] Google Vertex
- [ ] Groq
- [ ] XAI
- [ ] Amazon Bedrock
- [ ] Остальные (DeepSeek, Mistral, TogetherAI, ...)

## Блок L. Тесты
- [x] **Структура Swift Testing** — настроена ✅
  - `Tests/SwiftAISDKTests/*.swift` (12 файлов)
- [x] **V2/V3 типы** — 89 тестов (50 V2 + 39 V3) ✅
  - Покрытие: **100% типов V2 (17/17)** 🎯
  - 📋 Детали: `plan/review-2025-10-12-missing-types-tests.md`
- [x] **EventSourceParser** — 30 тестов ✅
- [x] **Provider Errors** — 26 тестов ✅
- [ ] перенос Vitest core tests — не начато
- [ ] перенос provider tests — не начато
- [ ] HTTP/SSE моки — не начато

## Блок M. Документация
- [-] **README** — структура обновлена, пример отсутствует ⚠️
  - Файл: `README.md`
- [ ] docs/Core.md — не начато
- [ ] docs/Tools.md — не начато
- [ ] docs/Streams.md — не начато
- [ ] docs/Providers — не начато
- [ ] docs/Testing — не начато

## Блок N. Релизы/CI
- [ ] Package.swift targets
- [ ] CI (swift build/test)
- [ ] changelog entries

## Блок O. Gateway/OIDC
- [ ] интерфейс gateway client — не начато
- [ ] AppAuth интеграция — не начато
- [ ] тесты токенов — не начато

---

## Архив сессий (2025-10-12)

<details>
<summary>Сессии 1-8: EventSourceParser, V2/V3 типы, Provider Errors</summary>

### Хронология выполнения
1. **Сессия 1**: EventSourceParser портирован (3 файла, 30 тестов, 100% паритет)
2. **Сессия 2**: Gap analysis V2 типов — выявлено 19 недостающих файлов
3. **Сессия 3**: V2 типы реализованы (17 файлов, ~1200 строк)
4. **Сессия 4**: Валидация + исправление 5 blocker-расхождений → 100% паритет
5. **Сессия 5**: Provider Errors (15 файлов, 26 тестов, 100% паритет)
6. **Сессия 6**: V2 типы тесты (25 тестов, 76% покрытие)
7. **Сессия 7**: V3 типы реализованы (17 файлов + preliminary field)
8. **Сессия 8**: V3 типы тесты (39 тестов, 100% паритет с V2)

### Ключевые решения
- V3 создан копированием V2 + добавление `preliminary?: Bool?` в ToolResult
- Usage поля сделаны опциональными (соответствует upstream)
- ResponseInfo использует плоскую структуру (не вложенную metadata)
- DataContent encode без обёрток (plain string/Data/URL)
- StreamPart расширен до 19 событий (было 10)

### Детальные ревью
- `plan/review-2025-10-12-v2types.md` — анализ расхождений V2
- `plan/review-2025-10-12-parser.md` — валидация EventSourceParser
- `plan/review-2025-10-12-missing-tests.md` — анализ покрытия тестами
- `plan/v2-vs-v3-analysis.md` — обоснование V3

</details>

---

## [validator][claude-code] Валидация 2025-10-12: Missing V2 Types Tests

### Статус: ✅ APPROVED

**Проверено:** 4 новых тестовых файла (+14 тестов)
- LanguageModelV2CallOptionsTests.swift (2 теста)
- LanguageModelV2CallWarningTests.swift (5 тестов)
- LanguageModelV2PromptTests.swift (5 тестов)
- LanguageModelV2ResponseMetadataTests.swift (2 теста)

**Результаты:**
- ✅ Все тесты проходят: **145/145 passed** (было 131/131)
- ✅ **100% паритет с upstream** TypeScript типами
- ✅ **0 критических расхождений** найдено
- ✅ **100% покрытие V2 типов** достигнуто (17/17)

**Upstream comparison:**
- Upstream V2 unit-тестов: **0**
- Наш SDK V2 unit-тестов: **50** 🏆
- **Мы лучше upstream** по test coverage

**Готовность:** ✅ Готов к коммиту

📋 **Детальный отчёт:** `plan/review-2025-10-12-missing-types-tests.md`

— validator/claude-code, 2025-10-12

---

> **Примечание**: Детальные описания сессий архивируются после завершения блоков. Текущий статус и следующие задачи см. в разделах A-O выше.
