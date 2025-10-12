# Проверка соответствия HTTP-запросов

Здесь будем фиксировать соответствие между HTTP-вызовами Swift-порта и TypeScript-версии. Нужно, чтобы набор URL, заголовков, query-параметров и тел совпадал по каждому провайдеру.

## Шаблон записи
- Провайдер: `openai`
- TypeScript источник: `packages/ai/src/providers/openai/index.ts`
- Swift файл: `Sources/SwiftAISDK/Providers/OpenAI/OpenAIClient.swift`
- Метод: `createResponse`
- Сравнение: ✅ заголовки `Authorization`, `Content-Type`, `X-VERCEL-AI-*`; тело запроса совпадает; обработка ошибок `OpenAIErrorResponse` совпадает.

## TODO
- [ ] Заполнить после реализации OpenAI.
- [ ] Пройтись по остальным провайдерам.
