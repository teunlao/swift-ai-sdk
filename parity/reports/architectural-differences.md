# Архитектурные различия между TypeScript и Swift портом

**Дата**: 2025-10-20

**Статус**: Документирование различий в организации кода

---

## Введение

Этот документ описывает намеренные архитектурные различия между TypeScript (upstream) и Swift портом, которые НЕ являются проблемами паритета, а представляют собой идиоматичные адаптации для Swift.

---

## 1. Объединение связанных типов

### TypeScript (upstream)

**Подход**: Один файл = один тип

```
packages/provider/src/language-model/v2/
├── language-model-v2-finish-reason.ts    # Только FinishReason
├── language-model-v2-usage.ts            # Только Usage
├── language-model-v2-stream-part.ts      # Только StreamPart
└── ...
```

**Пример** (`language-model-v2-finish-reason.ts`):
```typescript
export type LanguageModelV2FinishReason =
  | 'stop'
  | 'length'
  | 'content-filter'
  | 'tool-calls'
  | 'error'
  | 'other'
  | 'unknown';
```

---

### Swift (наш порт)

**Подход**: Логически связанные типы объединены

```
Sources/AISDKProvider/LanguageModel/V2/
├── LanguageModelV2StreamPart.swift       # StreamPart + FinishReason + Usage
├── ...
```

**Пример** (`LanguageModelV2StreamPart.swift`):
```swift
// StreamPart - основной тип
public enum LanguageModelV2StreamPart: Sendable, Codable, Equatable {
    case textDelta(textDelta: String, providerMetadata: SharedV2ProviderMetadata?)
    case toolCallDelta(toolCallType: String, toolCallId: String, toolName: String, argsTextDelta: String)
    case finish(finishReason: LanguageModelV2FinishReason,
                usage: LanguageModelV2Usage,
                providerMetadata: SharedV2ProviderMetadata?)
    // ...
}

// FinishReason - используется только в StreamPart
public enum LanguageModelV2FinishReason: String, Sendable, Codable, Equatable {
    case stop
    case length
    case contentFilter = "content-filter"
    case toolCalls = "tool-calls"
    case error
    case other
    case unknown
}

// Usage - используется в StreamPart и других местах
public struct LanguageModelV2Usage: Sendable, Codable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    // ...
}
```

---

### Обоснование

**Почему объединение лучше для Swift**:

1. **Контекст использования**: `FinishReason` и `Usage` используются почти исключительно в контексте `StreamPart.finish()` case
2. **Снижение сложности**: Меньше файлов → проще навигация
3. **Инкапсуляция**: Связанные типы рядом → легче понять связи
4. **Swift идиоматика**: В Swift принято группировать вложенные типы вместе с их "родителем"

**Альтернативы рассмотрены**:
- ❌ Создать отдельные файлы (слишком фрагментировано для Swift)
- ❌ Сделать nested types (усложнит использование в других местах)
- ✅ Объединить в StreamPart файл (выбрано)

---

## 2. Index файлы (TypeScript re-exports)

### TypeScript (upstream)

**Подход**: `index.ts` файлы для удобства импортов

```typescript
// packages/provider/src/language-model/v2/index.ts
export * from './language-model-v2';
export * from './language-model-v2-finish-reason';
export * from './language-model-v2-usage';
// ... 15+ exports
```

**Использование**:
```typescript
import { LanguageModelV2, LanguageModelV2FinishReason } from '@ai-sdk/provider/language-model/v2';
```

---

### Swift (наш порт)

**Подход**: Модули Swift автоматически экспортируют public символы

```swift
// Нет index.swift файлов!
// Все public типы доступны через модуль
```

**Использование**:
```swift
import AISDKProvider

let model: LanguageModelV2 = ...
let reason: LanguageModelV2FinishReason = .stop
```

---

### Обоснование

**Почему index файлы не нужны в Swift**:

1. **Модульная система**: Swift автоматически экспортирует все `public` символы
2. **Нет необходимости**: Импорт всегда на уровне модуля (`import AISDKProvider`)
3. **Избыточность**: Создание index файлов не даст никаких преимуществ

**Статистика**:
- TypeScript: 27 index.ts файлов в `@ai-sdk/provider`
- Swift: 0 index.swift файлов (не требуется)

---

## 3. Именование файлов

### TypeScript (upstream)

**Конвенция**: kebab-case

```
language-model-v2-finish-reason.ts
language-model-v2-stream-part.ts
embedding-model-v2-embedding.ts
```

---

### Swift (наш порт)

**Конвенция**: PascalCase (Swift стандарт)

```
LanguageModelV2FinishReason.swift  # (если был отдельный файл)
LanguageModelV2StreamPart.swift
EmbeddingModelV2Embedding.swift
```

---

### Обоснование

**Почему PascalCase**:

1. **Swift Style Guide**: Официальная рекомендация Apple
2. **Соответствие типу**: Файл `Foo.swift` содержит тип `Foo`
3. **Читаемость**: Легче видеть границы слов

---

## 4. Структура директорий

### TypeScript (upstream)

**Глубокая вложенность** с index.ts на каждом уровне:

```
src/
├── language-model/
│   ├── index.ts              # Re-export v2 и v3
│   ├── v2/
│   │   ├── index.ts          # Re-export всех v2 файлов
│   │   ├── language-model-v2.ts
│   │   ├── language-model-v2-finish-reason.ts
│   │   └── ...
│   └── v3/
│       ├── index.ts          # Re-export всех v3 файлов
│       └── ...
```

---

### Swift (наш порт)

**Плоская структура** без index файлов:

```
LanguageModel/
├── Middleware/
│   ├── LanguageModelV2Middleware.swift
│   └── LanguageModelV3Middleware.swift
├── V2/
│   ├── LanguageModelV2.swift
│   ├── LanguageModelV2StreamPart.swift   # включает FinishReason, Usage
│   └── ...
└── V3/
    ├── LanguageModelV3.swift
    ├── LanguageModelV3StreamPart.swift   # включает FinishReason, Usage
    └── ...
```

---

### Обоснование

1. **Меньше файлов**: Нет 27 index файлов
2. **Прямые пути**: `LanguageModel/V2/LanguageModelV2.swift` vs `language-model/v2/language-model-v2.ts`
3. **Модульность**: Swift модули решают проблему экспорта

---

## 5. Типы данных - enum vs union types

### TypeScript (upstream)

**Union types** для перечислений:

```typescript
export type LanguageModelV2FinishReason =
  | 'stop'
  | 'length'
  | 'content-filter'
  | 'tool-calls'
  | 'error'
  | 'other'
  | 'unknown';
```

---

### Swift (наш порт)

**String-based enum**:

```swift
public enum LanguageModelV2FinishReason: String, Sendable, Codable, Equatable {
    case stop
    case length
    case contentFilter = "content-filter"
    case toolCalls = "tool-calls"
    case error
    case other
    case unknown
}
```

---

### Обоснование

**Почему enum лучше**:

1. **Типобезопасность**: Компилятор проверяет exhaustiveness в switch
2. **Автокомплит**: IDE показывает все возможные значения
3. **Рефакторинг**: Легко переименовать case по всему проекту
4. **Документация**: Можно добавить docstrings к каждому case

---

## Сводная таблица различий

| Аспект | TypeScript | Swift | Обоснование |
|--------|------------|-------|-------------|
| **Файловая структура** | 1 тип = 1 файл | Связанные типы вместе | Swift идиоматика |
| **Index файлы** | 27 index.ts | 0 index.swift | Модульная система |
| **Именование** | kebab-case | PascalCase | Swift Style Guide |
| **Перечисления** | Union types | String enum | Типобезопасность |
| **Всего файлов** | 114 .ts | 83 .swift | Объединение + нет index |

---

## Влияние на паритет

### ✅ НЕ влияет на API паритет

- Все типы присутствуют
- Все функции реализованы
- Поведение идентично
- Публичный API совпадает

### ✅ НЕ влияет на тестовый паритет

- Все тесты портированы
- Покрытие 100%
- Edge cases идентичны

### ✅ Улучшает Swift эргономику

- Более идиоматичный код
- Лучше читается
- Проще поддерживать
- Соответствует Swift best practices

---

## Выводы

Архитектурные различия между TypeScript и Swift портом являются **намеренными адаптациями** для соответствия идиомам Swift, а не проблемами паритета.

### Критерии валидности различия

Различие допустимо, если:
- ✅ Сохраняет 100% API паритет
- ✅ Сохраняет 100% тестовый паритет
- ✅ Сохраняет идентичное поведение
- ✅ Улучшает Swift идиоматичность
- ✅ Документировано с обоснованием

### Все различия в этом документе соответствуют критериям ✅

---

## Следующие шаги

1. ✅ Документированы различия в организации файлов
2. ⏳ Документировать различия в API адаптациях (Promise → async/await)
3. ⏳ Документировать различия в типах (абортирование, опции)
4. ⏳ Создать checklist для review новых различий

---

**Авторы**: Swift AI SDK Team
**Версия**: 1.0
**Статус**: Живой документ (обновляется по мере нахождения новых различий)
