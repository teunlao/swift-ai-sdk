# Design Decisions Log

- **HTTPClient на базе URLSession.** Позволяет работать на macOS/iOS без сторонних зависимостей, поддерживает SSE и адаптируется через протоколы.
- **Telemetry через opentelemetry-swift.** Сохраняем совместимость с `@opentelemetry/api`, предоставляем no-op реализацию для окружений без OTel.
- **Namespace AISDK + alias ai.** Глобальные функции доступны через `AISDK.generateText`, алиас `ai` для короткой записи.
- **Сохранение LanguageModelV2.** Для паритета с TypeScript адаптер V2→V3 реализуется полностью.
- **Собственная семвер-линия.** Версии пакета — `0.x.y`, в changelog фиксируем upstream commit.
