# Playground / демо-приложение

## Цель
Обеспечить быстрое ручное тестирование `Swift AISDK` с реальными ключами провайдеров.

## Этапы
1. **CLI утилита**
   - Создать отдельный SwiftPM target (`SwiftAISDKPlayground`).
   - Реализовать команду `swift run playground generate-text ...` с чтением конфигурации из переменных окружения (`OPENAI_API_KEY` и т.д.).
   - Поддержать потоковый вывод (стрим дельт в терминал).
   - Добавить пример конфигурации (`.env.sample`).

2. **(Опционально) SwiftUI пример**
   - Создать минимальный macOS/iOS проект, показывающий поток сообщений (UIMessageStream).
   - Использовать его для демонстраций, но держать отдельно от основной библиотеки.

## Примечания
- Playground не часть CI; запуск вручную для smoke-проверок.
- Документировать в README, как включить (`swift run playground --help`).
- В будущем можно расширить поддержкой инструментов, reasoning, нескольких провайдеров.

---

## Текущее состояние (MVP CLI)

- Добавлен исполняемый таргет **`SwiftAISDKPlayground`** с зависимостью `swift-argument-parser`. Продукт `playground` доступен через `swift run playground …`.
- Реализована команда `chat`:
  ```bash
  swift run playground chat --model gpt-4o-mini --prompt "Hello" --stream
  ```
  Поддерживаются опции `--provider/-P`, `--prompt`, `--input-file`, `--stdin`, `--json-output`, `--stream`.
- Конфигурация загружается из переменных окружения и `.env` (см. обновлённый `.env.sample`). Для шлюза требуется `VERCEL_AI_API_KEY` (`AI_GATEWAY_API_KEY`) и, при необходимости, `AI_GATEWAY_BASE_URL`.
- Потоковый вывод использует SSE через `URLSession.bytes` и `EventSourceParser`; доступен на macOS 12+ (на более старых версиях CLI сообщает о неподдерживаемом режиме).
- Синхронный режим опирается на `LanguageModelV3.doGenerate`, стрим — на `doStream`; реализован минимальный **GatewayLanguageModel** для Vercel AI Gateway.
- Документация обновлена (`README.md`, `.env.sample`), добавлен smoke-тест `swift run playground chat …` в рабочий процесс.
