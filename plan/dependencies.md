# Зависимости Vercel AI SDK и стратегия замены в Swift-порте

## 1. Пакет `packages/ai`
- **Внутренние workspace-зависимости**: `@ai-sdk/gateway`, `@ai-sdk/provider`, `@ai-sdk/provider-utils`.
- **Внешняя зависимость**: `@opentelemetry/api@1.9.0` — API для OpenTelemetry (трейсинг, метрики).
- **Dev / peer**: `zod`, `@types/*`, `tsup`, `typescript`, и т.п.

**Swift-эквиваленты / стратегия**
- Оркестратор будет зависеть от наших собственных модулей `Gateway`, `Provider`, `ProviderUtils`, реализованных на Swift (скорее всего как сабтаргеты внутри Swift Package).
- Для телеметрии задействуем [opentelemetry-swift](https://github.com/open-telemetry/opentelemetry-swift) и обернём его в лёгкий адаптер (`TelemetryTracer`). Для окружений без OTel предоставим no-op реализацию, сохраняя API.
- `zod` в оригинале используется как peer для пользовательских схем. В Swift план: опираться на `Decodable`/`Codable` и предложить опциональный конвертер JSON Schema → Decodable через библиотеку [swift-jsonschema](https://github.com/kylef/JSONSchema.swift) или собственное представление. Интерфейсы описываем сразу, реализация подключается через протокол `SchemaValidator`.

## 2. Пакет `@ai-sdk/provider`
- **Внешняя зависимость**: `json-schema@^0.4.0` — типы/валидация JSON Schema.

**Стратегия**
- В Swift описываем структуру JSON Schema (`JSONSchemaValue`) и сериализацию. При необходимости допускаем подключение готовой библиотеки (например, `swift-jsonschema`) через тот же протокол. Главное — обеспечить передачу схем в провайдеры без потери данных.

## 3. Пакет `@ai-sdk/provider-utils`
- **Внутренняя зависимость**: `@ai-sdk/provider`.
- **Внешние**:
  - `@standard-schema/spec` — спецификация стандартных схем (TypeScript типы).
  - `eventsource-parser` — парсер SSE-потоков.

- **Peer** (опциональные): `arktype`, `effect`, `zod`, `@valibot/to-json-schema`.

**Стратегия**
- `@standard-schema/spec`: описываем соответствующие структуры в Swift (`StandardSchema`, `StandardSchemaProperty`). Совмещаем с JSON Schema, чтобы не дублировать форматы.
- `eventsource-parser`: пишем собственный SSE-парсер на Swift (`ServerSentEventParser`), опираясь на спецификацию. Для надёжности можно добавить модульные тесты на основе исходных фрагментов из JS-версии.
- Peer-зависимости в JS дают пользователю выбор валидатора. В Swift вводим протокол `SchemaValidator` и готовим адаптеры под популярные библиотеки (начинаем с встроенной реализации, позже можно добавить расширения под сторонние пакеты).

## 4. Пакет `@ai-sdk/gateway`
- **Внутренние зависимости**: `@ai-sdk/provider`, `@ai-sdk/provider-utils`.
- **Внешняя**: `@vercel/oidc@3.0.2` — реализация OpenID Connect клиента для Vercel AI Gateway.

**Стратегия**
- Функционал Gateway выносим в отдельный модуль (`SwiftAIGateway`). Для OIDC берём библиотеку [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) как базовую реализацию и создаём тонкий адаптер (`OIDCClient`). Для серверных окружений добавим упрощённый клиент на `URLSession` с ручной реализацией протокола.
- Первая итерация фокуса — ядро SDK и провайдеры без Gateway. Интерфейсы для Gateway/OIDC проектируем сразу, чтобы позже подключить реализацию без изменений публичного API.

## 5. Пакеты провайдеров (OpenAI, Anthropic, Google, Groq и т.д.)
- Каждая реализация в TypeScript добавляет свои HTTP-клиенты, авторизацию, мапперы моделей.
- Общие зависимости: `@ai-sdk/provider`, `@ai-sdk/provider-utils`. Дополнительно отдельные пакеты могут тянуть `@azure/core-client`, `node-fetch`, специализированные SDK.

**Стратегия**
- В Swift организуем единый слой HTTP (`LLMHTTPClient`) на `URLSession` с поддержкой ретраев, таймаутов и SSE.
- Специфичные SDK (например, Azure) реализуем через REST API: описываем конфигурацию и выполняем запросы вручную, не полагаясь на тяжёлые SDK.
- Стартуем с OpenAI (Responses API), затем Anthropic/Google; по мере готовности повторяем структуру для остальных провайдеров.

## 6. Инструменты разработки и тестирования
- `vitest`, `msw`, `@edge-runtime/vm`, `@types/*`, `tsup`, `eslint`, `prettier`, `typescript`, `tsx` — используются для разработки и тестов в TypeScript.

**Связь со Swift**
- Эти инструменты заменяются на Swift Testing/XCTest и собственные фикстуры JSON; разработки для TypeScript нам не понадобятся.

## 7. Прочие компоненты репозитория
- `packages/ai-elements` (UI-компоненты) — зависит от React/shadcn; в Swift порте не переносим, но можно воспроизвести ключевые интерфейсы (например, state-машины) в виде SwiftUI-примеров.
- `packages/gateway` — см. пункт 4.
- `packages/test-server` — вспомогательный сервер на Node. В Swift создадим аналог на базе `URLProtocol` (в тестах) и, при необходимости, лёгкий HTTP-сервер (например, на Vapor).

## 8. Общие выводы
- Критические внешние зависимости, требующие Swift-аналога: `@opentelemetry/api`, `eventsource-parser`, `json-schema`, `@vercel/oidc`.
- Остальные — dev-инфраструктура TypeScript; в Swift их заменяют штатные инструменты.
- Проектируем API через протоколы расширения, чтобы поддерживать разные валидаторы/схемы/интеграции аналогично TypeScript-версии.

## 9. Следующие шаги
1. Описать структуру модулей Swift Package (`Core`, `Streams`, `Tools`, `Registry`, `Providers`, `Gateway`).
2. Специфицировать протоколы/структуры для Telemetry, HTTP и Schema Validation (no-op реализации по умолчанию).
3. Спланировать реализацию SSE-парсера и базового HTTP-клиента.
