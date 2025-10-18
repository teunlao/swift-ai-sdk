import Foundation
@testable import SwiftAISDK

/**
 Simple tracer implementation for testing telemetry integration.

 Port of `@ai-sdk/ai/src/test/mock-tracer.ts` adapted to the Swift tracer/span
 protocols. Captures started spans and stores basic metadata for assertions.
 */
final class MockTracer: Tracer, @unchecked Sendable {
    struct SpanRecord: Equatable, Sendable {
        let name: String
        let attributes: Attributes
        let events: [SpanEvent]
        let status: SpanStatusRecord?
    }

    struct SpanEvent: Equatable, Sendable {
        let name: String
        let attributes: Attributes?
    }

    struct SpanStatusRecord: Equatable, Sendable {
        let code: SpanStatusCode
        let message: String?
    }

    final class MockSpan: Span, @unchecked Sendable {
        let name: String
        private var attributesStorage: Attributes
        private var eventsStorage: [(name: String, attributes: Attributes?)] = []
        private var statusStorage: SpanStatus?
        private let lock = NSLock()
        private let context: SpanContext

        init(name: String, attributes: Attributes?) {
            self.name = name
            self.attributesStorage = attributes ?? [:]
            self.context = SpanContext(traceId: "test-trace-id", spanId: "test-span-id", traceFlags: 0)
        }

        var attributes: Attributes {
            withLock { attributesStorage }
        }

        var events: [(name: String, attributes: Attributes?)] {
            withLock { eventsStorage }
        }

        var status: SpanStatus? {
            withLock { statusStorage }
        }

        func spanContext() -> SpanContext {
            context
        }

        @discardableResult
        func setAttribute(_ key: String, value: AttributeValue) -> Self {
            withLock {
                attributesStorage[key] = value
            }
            return self
        }

        @discardableResult
        func setAttributes(_ attributes: Attributes) -> Self {
            withLock {
                for (key, value) in attributes {
                    attributesStorage[key] = value
                }
            }
            return self
        }

        @discardableResult
        func addEvent(_ name: String, attributes: Attributes?) -> Self {
            withLock {
                eventsStorage.append((name: name, attributes: attributes))
            }
            return self
        }

        @discardableResult
        func setStatus(_ status: SpanStatus) -> Self {
            withLock {
                statusStorage = status
            }
            return self
        }

        @discardableResult
        func updateName(_ name: String) -> Self {
            // Name updates are ignored for mock purposes.
            return self
        }

        func end() {
            // No-op for tests.
        }

        func isRecording() -> Bool {
            false
        }

        @discardableResult
        func recordException(_ exception: ExceptionEvent) -> Self {
            let attributes: Attributes = [
                "exception.type": .string(exception.name ?? "Error"),
                "exception.message": .string(exception.message ?? ""),
                "exception.stack": .string(exception.stack ?? "")
            ]
            withLock {
                eventsStorage.append((name: "exception", attributes: attributes))
            }
            return self
        }

        private func withLock<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }
    }

    private let lock = NSLock()
    private var spans: [MockSpan] = []

    var spanRecords: [SpanRecord] {
        withLock {
            spans.map { span in
                SpanRecord(
                    name: span.name,
                    attributes: span.attributes,
                    events: span.events.map { event in SpanEvent(name: event.name, attributes: event.attributes) },
                    status: span.status.map { SpanStatusRecord(code: $0.code, message: $0.message) }
                )
            }
        }
    }

    func startSpan(name: String, options: SpanOptions?) -> any Span {
        let span = MockSpan(name: name, attributes: options?.attributes)
        withLock {
            spans.append(span)
        }
        return span
    }

    func startActiveSpan<T>(
        _ name: String,
        options: SpanOptions?,
        _ fn: @Sendable (any Span) async throws -> T
    ) async rethrows -> T {
        let span = MockSpan(name: name, attributes: options?.attributes)
        withLock {
            spans.append(span)
        }
        return try await fn(span)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
