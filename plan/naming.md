# Неймспейс и глобальный API

- Основной публичный неймспейс: `AISDK` (enum).
- Глобальные функции доступны как `AISDK.generateText`, `AISDK.streamText`.
- В README указываем, что можно добавить короткий alias:
  ```swift
  enum ai {}
  extension ai {
      static func generateText(...) -> GenerateTextResult {
          try await AISDK.generateText(...)
      }
  }
  ```
  (Alias предоставим из коробки: `public enum ai {}` со статическими методами-прокси.)
- Все публичные типы именуем UpperCamelCase, следуя стилю Swift и совпадая с TypeScript названии.
