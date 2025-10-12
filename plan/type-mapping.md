# Карта TypeScript → Swift типов

| TypeScript тип                             | Назначение                                   | Swift аналог                   |
|-------------------------------------------|----------------------------------------------|---------------------------------|
| `LanguageModelV2`                         | Контракт провайдера v2                       | `LanguageModelV2` (struct/protocol)
| `LanguageModelV3`                         | Новый контракт провайдера                    | `LanguageModelV3`
| `LanguageModelV2StreamPart`               | Части стрима (start/delta/end)               | `LanguageModelV2StreamPart` (enum)
| `StreamTextResult`                        | Результат streamText                         | `StreamTextResult`
| `GenerateTextResult`                      | Результат generateText                       | `GenerateTextResult`
| `ToolDefinition`, `FunctionTool`, `ToolCall` | Описание инструментов                        | Идентичные структуры/enums
| `Usage`                                   | Токен-usage                                  | `Usage` struct
| `CallWarning`                             | Предупреждения                              | `CallWarning` enum
| `FinishReason`                            | Причина завершения                           | `FinishReason` enum
| `ProviderMetadata`                        | Метаданные провайдеров                       | `ProviderMetadata` (typealias/struct)
| `Reasoning`, `ReasoningDelta`             | Поток reasoning                              | `ReasoningPart` enum
| `StandardizePrompt` types                 | Нормализация промптов                        | Соответствующие struct/enum
| `AIError`                                 | Ошибки SDK                                   | `AIError` enum + associated values

Дополнительно: все union-типы → enum с associated values; `Record<string, T>` → `Dictionary<String, T>`; `Uint8Array` → `Data`.
