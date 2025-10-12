# LanguageModelV2 vs V3 Analysis

> Документ создан: 2025-10-12
>
> Цель: Объяснить зачем нужен V3, в чём отличия от V2, и почему мы реализуем обе версии

## TL;DR

**V3 - это новая версия спецификации provider interface**, созданная для:
- Backward compatibility (V2 провайдеры продолжают работать)
- Extensibility (добавление новых фич без breaking changes)
- Future-proofing (подготовка к v6.0 архитектуре)

**Core SDK использует V3**, поэтому нам критично его реализовать.

---

## 1. Историческая справка

### Timeline
- **2024-2025**: AI SDK 5.x использует V2 спецификации
- **Sept 19, 2025**: Начата работа над V3 spec (milestone v5.1/v6.0)
- **Oct 2025**: V3 интегрирован в beta версии
- **Текущее состояние**: SDK поддерживает `LanguageModel = string | LanguageModelV2 | LanguageModelV3`

### Причины создания V3

#### 1. **Semantic Versioning для Provider Specs**
Vercel выделили спецификации провайдеров в отдельные версионируемые контракты:
- V2 - stable, frozen (для backward compatibility)
- V3 - active development (для новых фич)
- Это позволяет эволюционировать API без breaking changes

#### 2. **Architectural Modernization (v6.0 milestone)**
V3 создан как часть масштабной модернизации архитектуры AI SDK:
- Переосмысление provider interface
- Поддержка новых AI capabilities (reasoning models, tool execution)
- Улучшенная extensibility через provider metadata/options

#### 3. **Community Providers Compatibility**
Старые community-провайдеры остаются на V2:
```typescript
// Оба работают одновременно
export type LanguageModel =
  | string
  | LanguageModelV2  // legacy providers
  | LanguageModelV3  // new providers
```

#### 4. **Extensibility для новых AI capabilities**
- Reasoning models (Claude Sonnet extended thinking)
- Provider-executed tools (preliminary results)
- Native streaming improvements
- Provider-specific metadata evolution

---

## 2. Технические отличия V2 vs V3

### 2.1 Структурные различия

**Файловая структура**: Идентична (19 файлов)
```
v2/                                v3/
├── language-model-v2.ts          ├── language-model-v3.ts
├── language-model-v2-text.ts     ├── language-model-v3-text.ts
├── language-model-v2-tool-*.ts   ├── language-model-v3-tool-*.ts
└── ...                           └── ...
```

**Общее кол-во кода**: ~1000 строк (одинаково для V2 и V3)

### 2.2 Различия в типах

#### **Основное отличие #1: ToolResult.preliminary**

**V2:**
```typescript
export type LanguageModelV2ToolResult = {
  type: 'tool-result';
  toolCallId: string;
  toolName: string;
  result: JSONValue;
  isError?: boolean;
  providerExecuted?: boolean;
  providerMetadata?: SharedV2ProviderMetadata;
}
```

**V3:**
```typescript
export type LanguageModelV3ToolResult = {
  type: 'tool-result';
  toolCallId: string;
  toolName: string;
  result: JSONValue;
  isError?: boolean;
  providerExecuted?: boolean;

  // 🆕 NEW in V3
  preliminary?: boolean;  // <--- ЕДИНСТВЕННОЕ НОВОЕ ПОЛЕ

  providerMetadata?: SharedV3ProviderMetadata;
}
```

**Назначение `preliminary`:**
- Позволяет отправлять **инкрементальные обновления** tool results
- Пример: preview изображений, промежуточные результаты
- Preliminary результаты **заменяют** друг друга
- **Обязательно** должен быть финальный non-preliminary результат

**Use case:**
```swift
// Provider отправляет preview
ToolResult(preliminary: true, result: "Loading image...")
ToolResult(preliminary: true, result: "50% loaded...")
ToolResult(preliminary: true, result: "95% loaded...")
// Финальный результат
ToolResult(preliminary: false, result: actualImageData)
```

#### **Отличие #2: Переименование типов**

Все типы переименованы `V2` → `V3`:
- `LanguageModelV2` → `LanguageModelV3`
- `SharedV2ProviderMetadata` → `SharedV3ProviderMetadata`
- `SharedV2ProviderOptions` → `SharedV3ProviderOptions`
- `SharedV2Headers` → `SharedV3Headers`

#### **Отличие #3: specificationVersion**

```typescript
// V2
export type LanguageModelV2 = {
  readonly specificationVersion: 'v2';
  // ...
}

// V3
export type LanguageModelV3 = {
  readonly specificationVersion: 'v3';
  // ...
}
```

### 2.3 Что НЕ изменилось

**Идентичная функциональность:**
- ✅ Content types (Text, Reasoning, File, Source)
- ✅ Tool types (ToolCall, ToolChoice, FunctionTool, ProviderDefinedTool)
- ✅ Prompt structure (Message roles, parts)
- ✅ Stream events (19 типов StreamPart)
- ✅ CallOptions (все поля одинаковые)
- ✅ Usage, ResponseMetadata, CallWarning

**Вывод**: V3 - это почти 1:1 копия V2 с минимальными добавлениями.

---

## 3. Зачем V3 нужен в Swift AI SDK

### 3.1 Core SDK требует V3

**Факт**: `generateText` использует `LanguageModelV3`:
```typescript
// packages/ai/src/generate-text/generate-text.ts
import {
  LanguageModelV3,           // <-- V3, не V2!
  LanguageModelV3Content,
  LanguageModelV3ToolCall,
} from '@ai-sdk/provider';
```

**Вывод**: Без V3 мы не можем реализовать `generateText`, `streamText`, и другие core функции.

### 3.2 V2 - это legacy

V2 остается для:
- ✅ Backward compatibility с существующими провайдерами
- ✅ Reference implementation
- ✅ Тесты на совместимость

Но **вся новая функциональность** будет на V3.

### 3.3 Future-proofing

V3 позволяет добавлять новые поля в будущем:
- Multi-modal reasoning
- Improved tool execution flows
- Provider-specific streaming optimizations
- Без breaking changes для V2 провайдеров

---

## 4. Стратегия реализации для Swift SDK

### 4.1 Что реализуем

**V2 типы** (✅ уже реализовано):
- 17 типов в `Sources/SwiftAISDK/Provider/LanguageModel/V2/`
- 36 тестов в `Tests/.../LanguageModelV2*Tests.swift`
- Полный паритет с upstream

**V3 типы** (🚧 следующий шаг):
- 17 типов в `Sources/SwiftAISDK/Provider/LanguageModel/V3/`
- Копия V2 + добавить `preliminary?: Bool?` в ToolResult
- Переименовать все `V2` → `V3`
- Скопировать и адаптировать тесты

**Shared типы**:
- `SharedV3ProviderMetadata`, `SharedV3ProviderOptions`, `SharedV3Headers`
- Идентичны V2, просто rename

### 4.2 План реализации V3

```
1. Create Shared V3 types (~5 мин)
   - SharedV3ProviderMetadata.swift
   - SharedV3ProviderOptions.swift
   - SharedV3Headers.swift

2. Copy V2 → V3 directory (массовое копирование)
   - cp -r V2/ V3/

3. Mass rename V2 → V3 (~10 мин)
   - Все файлы, типы, импорты
   - specificationVersion: 'v3'

4. Add preliminary field (~2 мин)
   - LanguageModelV3ToolResult: preliminary?: Bool?

5. Tests (~15 мин)
   - Copy V2 tests → V3 tests
   - Адаптировать имена типов
   - Добавить тесты для preliminary field

6. Verify (~5 мин)
   - swift build
   - swift test
   - Убедиться что все 92+36 тестов проходят
```

**Оценка**: 40-50 минут работы

### 4.3 Приоритеты

**High Priority:**
1. ✅ V2 types (done - 100% parity)
2. 🔥 **V3 types** ← СЛЕДУЮЩИЙ ШАГ
3. Provider utils (HTTP, id generators)
4. Core generateText/streamText

**V3 критичен** потому что:
- Core SDK зависит от V3
- Без V3 невозможен дальнейший прогресс
- V3 - это foundation для всего остального

---

## 5. Выводы

### Ключевые тезисы

1. **V3 ≈ V2 + minimal changes**
   - Единственное реальное отличие: `preliminary?: boolean` в ToolResult
   - Остальное - просто переименование типов

2. **V3 - это semantic versioning**
   - Не про breaking changes (их почти нет)
   - Про архитектурную готовность к будущим изменениям
   - Про backward compatibility для ecosystem

3. **Нам нужны оба V2 и V3**
   - V2: для reference, тестов, провайдеров
   - V3: для core SDK, новых фич, будущего

4. **Реализация тривиальна**
   - Copy V2 → V3
   - Rename
   - Add `preliminary` field
   - Done!

### Рекомендация

**Реализовать V3 сейчас** потому что:
- ✅ Минимальные усилия (40-50 минут)
- ✅ Критично для дальнейшего прогресса
- ✅ Простая миграция (почти 1:1 с V2)
- ✅ Future-proof архитектура

---

## 6. Ссылки

- [GitHub Issue #8763 - Create v3 provider model specs](https://github.com/vercel/ai/issues/8763)
- [GitHub Issue #9018 - V3 spec type changes](https://github.com/vercel/ai/issues/9018)
- [PR #8877 - LanguageModelV3 implementation](https://github.com/vercel/ai/pull/8877)
- [AI SDK 5 Blog Post](https://vercel.com/blog/ai-sdk-5)
- Upstream reference: `external/vercel-ai-sdk/packages/provider/src/language-model/v3/`

---

## Дата создания
2025-10-12 14:05 UTC

## Автор анализа
Claude Code (agent-executor)
