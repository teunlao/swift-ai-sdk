# Найденные проблемы паритета

**Дата создания**: 2025-10-20
**Статус**: Активный трекинг

---

## Формат записи

```markdown
### [ID] Краткое описание проблемы

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Status**: OPEN | IN_PROGRESS | RESOLVED | WONTFIX
**Package**: AISDKProvider | AISDKProviderUtils | SwiftAISDK
**Category**: API | Types | Tests | Behavior

**Файлы**:
- TS: `path/to/upstream.ts`
- Swift: `path/to/Swift.swift`

**Описание**:
Детальное описание проблемы.

**Ожидается** (по upstream):
Что должно быть согласно TypeScript версии.

**Реально** (в Swift):
Что есть сейчас в Swift порте.

**Решение**:
Предлагаемое решение.

**Обновлено**: YYYY-MM-DD
```

---

## Статистика

- **Всего проблем**: 2
- **Критических**: 0
- **Высокий приоритет**: 1
- **Средний приоритет**: 0
- **Низкий приоритет**: 1
- **Решено**: 1

---

## 🟢 Критические (CRITICAL)

_Проблемы, которые блокируют использование или нарушают корректность_

### Статус: Нет критических проблем ✅

---

## 🟡 Высокий приоритет (HIGH)

_Важные различия, которые должны быть исправлены в ближайшее время_

### [ISSUE-001] Отсутствует inject-json-instruction функция

**Severity**: HIGH
**Status**: OPEN
**Package**: AISDKProviderUtils
**Category**: API

**Файлы**:
- TS: `provider-utils/src/inject-json-instruction.ts`
- Swift: Отсутствует

**Описание**:
Функция `injectJsonInstruction` и `injectJsonInstructionIntoMessages` отсутствуют в Swift порте. Эти функции используются для добавления JSON schema инструкций в промпты для моделей, которые не поддерживают structured output нативно.

**Ожидается** (по upstream):
```typescript
export function injectJsonInstruction({
  prompt,
  schema,
  schemaPrefix,
  schemaSuffix,
}: {
  prompt?: string;
  schema?: JSONSchema7;
  schemaPrefix?: string;
  schemaSuffix?: string;
}): string

export function injectJsonInstructionIntoMessages({
  messages,
  schema,
  schemaPrefix,
  schemaSuffix,
}: {
  messages: LanguageModelV3Prompt;
  schema?: JSONSchema7;
  schemaPrefix?: string;
  schemaSuffix?: string;
}): LanguageModelV3Prompt
```

**Реально** (в Swift):
Функция отсутствует.

**Использование в upstream**:
- Используется в Mistral provider
- Экспортируется из `@ai-sdk/provider-utils`
- Также есть копия в `@ai-sdk/ai/src/generate-object/`

**Решение**:
1. Портировать обе функции в AISDKProviderUtils
2. Создать тесты
3. Документировать использование

**Приоритет**: HIGH - используется в production providers (Mistral)

**Создано**: 2025-10-20

---

## 🟠 Средний приоритет (MEDIUM)

_Различия, которые нужно исправить, но не блокируют работу_

_Пока нет_

---

## 🔵 Низкий приоритет (LOW)

_Мелкие несоответствия, улучшения_

### [ISSUE-002] Отсутствует test/mock-id утилита

**Severity**: LOW
**Status**: OPEN
**Package**: AISDKProviderUtils
**Category**: Tests

**Файлы**:
- TS: `provider-utils/src/test/mock-id.ts`
- Swift: Отсутствует

**Описание**:
Тестовая утилита `mockId` для генерации предсказуемых ID в тестах отсутствует в Swift порте.

**Ожидается** (по upstream):
```typescript
export function mockId({
  prefix = 'id',
}: {
  prefix?: string;
} = {}): () => string {
  let counter = 0;
  return () => `${prefix}-${counter++}`;
}
```

**Реально** (в Swift):
Утилита отсутствует. Возможно, Swift тесты используют другой подход для генерации тестовых ID.

**Решение**:
- Опция 1: Портировать утилиту для консистентности
- Опция 2: Использовать Swift native подход (UUID, fixed strings)
- Опция 3: WONTFIX если не используется в тестах

**Приоритет**: LOW - тестовая утилита, не влияет на функциональность

**Создано**: 2025-10-20

---

## ✅ Решено (RESOLVED)

### [RESOLVED-001] FinishReason и Usage типы отсутствуют

**Severity**: CRITICAL → RESOLVED
**Status**: RESOLVED
**Package**: AISDKProvider
**Category**: Types

**Файлы**:
- TS: `language-model/v2/language-model-v2-finish-reason.ts`
- TS: `language-model/v2/language-model-v2-usage.ts`
- Swift: `LanguageModel/V2/LanguageModelV2StreamPart.swift`

**Описание**:
Изначально казалось, что типы FinishReason и Usage отсутствуют в Swift порте.

**Решение**:
Проверка показала, что типы присутствуют, но объединены в файл `LanguageModelV2StreamPart.swift`. Это не проблема паритета, а архитектурное решение.

**Результат**:
- Типы найдены ✅
- Документировано в `architectural-differences.md` ✅
- Mapping обновлен ✅

**Решено**: 2025-10-20

---

## Шаблон для новой проблемы

```markdown
### [ISSUE-XXX] Название проблемы

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Status**: OPEN
**Package**: AISDKProvider | AISDKProviderUtils | SwiftAISDK
**Category**: API | Types | Tests | Behavior

**Файлы**:
- TS: `path/to/file.ts`
- Swift: `path/to/File.swift`

**Описание**:
...

**Ожидается**:
...

**Реально**:
...

**Решение**:
...

**Создано**: YYYY-MM-DD
```

---

## История изменений

| Дата | Событие | Автор |
|------|---------|-------|
| 2025-10-20 | Создан файл трекинга проблем | Claude |
| 2025-10-20 | Решена RESOLVED-001 (FinishReason/Usage) | Claude |
