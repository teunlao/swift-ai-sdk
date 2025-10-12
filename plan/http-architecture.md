# HTTP и SSE архитектура

## Клиент
- Основной протокол `HTTPClient` с методами `send(request:)` возвращающими `HTTPResponse`.
- Реализация по умолчанию `URLSessionHTTPClient` (supports JSON, SSE, retries, telemetry hooks).
- Поддержка middleware (как в TS wrap-provider): массив interceptors, позволяющих модифицировать запрос/ответ.

## SSE
- `ServerSentEventParser` — разбирает поток байтов в события (данные, event, id, retry).
- `SSEStream` — обёртка над `AsyncThrowingStream<ServerSentEvent>`, прокидывает cancel.
- Провайдеры используют SSE для `streamText` и `textStream`. Тесты — через фикстуры.

## Ошибки
- Ошибки HTTP (статусы 4xx/5xx) → маппинг на `AIError.providerError`.
- Parse errors → `AIError.invalidResponse`.
- Предусмотреть `Retry-After` и стратегии повторов (конфигурируемые).

## Заголовки
- Таблица default headers (User-Agent, Accept, X-VERCEL-AI-*).
- Конфигурация через `ProviderSettings` (ключи, базовые URL, custom headers).

## Телеметрия
- Хуки перед/после запроса (OpenTelemetry tracer).

## TODO
- После начала реализации дополнить ссылками на конкретные Swift-файлы и схемы потоков.
