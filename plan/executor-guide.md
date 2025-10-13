# Руководство для агента‑исполнителя (Swift AI SDK)

> Этот документ описывает обязанности исполнителя, рабочий процесс, чек‑лист паритета и стандартный промпт для запуска новой сессии. Все записи, добавленные исполнителем в план, помечаются префиксом `[executor]`.

## Роль и цели
- Реализовать Swift‑порт Vercel AI SDK 1:1 с оригиналом (API, поведение, типы, тесты, документация).
- Следовать структуре проекта (3 пакета: `AISDKProvider`, `AISDKProviderUtils`, `SwiftAISDK`) и принятым правилам.
- Писать код и тесты с учётом минимальных расхождений и документировать прогресс.

## Архитектура пакетов

**Проект организован в 3 SwiftPM пакета** (matching upstream `@ai-sdk` architecture):

### 📦 AISDKProvider — Foundation Package
**Location**: `Sources/AISDKProvider/`
**Dependencies**: None (foundation)
**Upstream**: `@ai-sdk/provider`

**Что размещать здесь**:
- Protocol definitions (LanguageModel V2/V3, EmbeddingModel, ImageModel, etc.)
- Provider-specific types (CallOptions, CallWarning, StreamPart, etc.)
- Provider errors (APICallError, InvalidPromptError, etc.)
- JSONValue universal JSON type
- Middleware protocol interfaces (LanguageModelV2Middleware, LanguageModelV3Middleware)
- Shared types (V2/V3 shared definitions)

**Import statement**: No imports (foundation package)

### 🔧 AISDKProviderUtils — Utilities Package
**Location**: `Sources/AISDKProviderUtils/`
**Dependencies**: AISDKProvider
**Upstream**: `@ai-sdk/provider-utils`

**Что размещать здесь**:
- HTTP utilities (GetFromAPI, PostToAPI, ResponseHandler, CombineHeaders, etc.)
- JSON utilities (ParseJSON, SecureJsonParse, FixJson, etc.)
- Schema definitions (Schema, FlexibleSchema, StandardSchema)
- Type validation (ValidateTypes)
- Tool definitions (Tool, DynamicTool, ToolSet)
- Data handling (DataContent, SplitDataUrl, ContentPart)
- Utility functions (GenerateID, Delay, LoadSettings, IsUrlSupported, etc.)
- Media type detection and handling

**Import statement**: `import AISDKProvider`

### 🚀 SwiftAISDK — Main SDK Package
**Location**: `Sources/SwiftAISDK/`
**Dependencies**: AISDKProvider, AISDKProviderUtils, EventSourceParser
**Upstream**: `@ai-sdk/ai`

**Что размещать здесь**:
- High-level SDK functions (generateText, streamText, etc.)
- Prompt conversion and standardization
- Call settings preparation
- Tool execution framework
- Provider registry and model resolution
- Middleware implementations (DefaultSettings, ExtractReasoning, SimulateStreaming)
- Gateway integration
- Telemetry and logging
- SDK-specific errors (NoSuchToolError, InvalidToolInputError, etc.)
- Testing utilities (MockLanguageModelV2, MockLanguageModelV3)

**Import statements**:
```swift
import AISDKProvider
import AISDKProviderUtils
```

### Граф зависимостей
```
AISDKProvider (no deps)
    ↑
AISDKProviderUtils
    ↑
SwiftAISDK + EventSourceParser
```

### Правила размещения нового кода

**Проверка upstream location**:
1. Найти файл в `external/vercel-ai-sdk/packages/`
2. Определить пакет: `provider/`, `provider-utils/`, или `ai/`
3. Поместить в соответствующий Swift пакет

**Примеры**:
- `packages/provider/src/language-model/v3/language-model-v3.ts` → `Sources/AISDKProvider/LanguageModel/V3/LanguageModelV3.swift`
- `packages/provider-utils/src/delay.ts` → `Sources/AISDKProviderUtils/Delay.swift`
- `packages/ai/src/generate-text/generate-text.ts` → `Sources/SwiftAISDK/GenerateText/GenerateText.swift`

**Tests organization**:
- `Tests/AISDKProviderTests/` — для AISDKProvider
- `Tests/AISDKProviderUtilsTests/` — для AISDKProviderUtils
- `Tests/SwiftAISDKTests/` — для SwiftAISDK

## Основные обязанности
1. **Планирование**
   - Перед работой свериться с Task Master (`mcp__taskmaster__get_tasks`), `plan/principles.md`, `plan/dependencies.md`.
   - Если по ходу выявлены дополнительные задачи ― добавлять их в Task Master (`mcp__taskmaster__add_task`) с префиксом `[executor]`.
2. **Реализация**
   - Портировать типы/модули/тесты, придерживаясь структуры upstream (`packages/ai`, `packages/provider`, `eventsource-parser`, и т.д.).
   - Обеспечивать тестируемость (Swift Testing), повторяя оригинальные фикстуры.
   - Обновлять документацию (README, docs/*) при добавлении новой публичной поверхности.
3. **Проверка**
   - После каждого блока работы запускать `swift build` и `swift test` (и дополнительные команды, если требуются).
   - Обновлять статусы задач в Task Master (`mcp__taskmaster__set_task_status`).
4. **Коммуникация**
   - Не выполнять коммит/пуш без явного разрешения владельца репозитория.
   - Передавать валидатору/заказчику информацию о готовности блока и известных ограничениях.

## Чек‑лист перед завершением блока
1. Публичные API и типы совпадают с TS-версией.
2. Поведение (ошибки, заголовки, SSE, retries) повторяет оригинальный код.
3. Тесты Swift Testing покрывают сценарии из JS тестов; `swift test` зелёный.
4. Задача обновлена в Task Master (статус `done`).
5. Документация/README/CHANGELOG приведены в актуальное состояние.
6. Убедиться, что в рабочем дереве нет «лишних» незакоммиченных файлов.

## Что обязательно фиксировать в Task Master
- Начало/завершение работы над отдельными файлами/подсистемами через статусы задач.
- Статус тестов и билда в деталях задачи (используя `design-decisions.md` для важных решений).
- Все находки по ходу исследования кода документировать в задачах или добавлять новые задачи.

> Подпись и метка времени: каждый комментарий/пометка/изменение, оставленные исполнителем в файлах `plan/*`, обязаны содержать подпись автора (роль и модель/движок) и точное время в стандартизированном формате (UTC, ISO‑8601/RFC3339).
> 
> Единый формат времени: `YYYY-MM-DDTHH:MM:SSZ` (UTC)
> 
> Допустимые формы подписи:
> - В начале записи: `YYYY-MM-DDTHH:MM:SSZ [executor][gpt-5] ...`
> - В конце абзаца: `... — agent‑executor/gpt‑5 @ YYYY-MM-DDTHH:MM:SSZ`
> 
> Быстро получить метку (macOS/Linux): `date -u +"%Y-%m-%dT%H:%M:%SZ"`
> 
> Подпись и метка времени обязательны для всех новых строк/параграфов, добавляемых исполнителем в план.

## Работа с документами в `plan/`
- **Task Master** ― управление задачами, статусами, зависимостями.
- **`plan/design-decisions.md`** ― документировать важные решения/отклонения от оригинала.
- **`plan/providers.md`, `plan/tests.md`, `plan/dependencies.md`** ― дополнять при переносе соответствующих областей.

## Стандартный рабочий цикл
1. Прочитать актуальные документы плана и получить следующую задачу (`mcp__taskmaster__next_task`).
2. Уточнить upstream-референсы (коммит/версия) и сопоставить файлы.
3. Реализовать функциональность в Swift (порт + адаптация).
4. Написать/адаптировать тесты.
5. Запустить `swift build` и `swift test` (при необходимости – дополнительные команды).
6. Обновить статус задачи в Task Master (`mcp__taskmaster__set_task_status`).
7. Подготовить summary/вопросы для валидатора или владельца репо.

## Что запрещено без отдельного разрешения
- Коммитить и пушить изменения в удалённый репозиторий.
- Вносить изменения, нарушающие паритет с Vercel AI SDK, без согласования.
- Игнорировать failing-тесты (допустимо временно пометить TODO в плане, но не оставлять баги без записи).

## Промпт для запуска исполнителя
```
Ты — агент‑исполнитель Swift AI SDK. Твоя задача — портировать очередной модуль из Vercel AI SDK на Swift 1:1.

Контекст:
- Upstream: Vercel AI SDK <версия/коммит> (см. README/CHANGELOG).
- Исходники для сравнения: external/vercel-ai-sdk (и др. external/* при необходимости).
- План/процесс: см. файлы в каталоге plan/, особенно principles/tests/providers и Task Master.

Сделай:
1) Получи следующую задачу из Task Master (`mcp__taskmaster__next_task`).
2) Изучи соответствующие файлы плана и upstream.
3) Реализуй функциональность в Swift, сохранив структуру и поведение.
4) Адаптируй/добавь тесты (Swift Testing).
5) Запусти `swift build` и `swift test`.
6) Обнови статус задачи в Task Master (`mcp__taskmaster__set_task_status --id=X --status=done`).
7) Подготовь краткое summary/email для валидатора или владельца проекта.

Никогда не коммить/пушить без явного разрешения.
```

## Definition of Done для исполнителя
- Код совпадает с upstream по API и поведению.
- Тесты воспроизводят сценарии оригинала и проходят локально.
- План/документация обновлены.
- Валидатор или владелец может однозначно продолжить работу без дополнительных вопросов.

---
Последний редактор: агент‑исполнитель. Обновлять этот файл при уточнении процесса.
