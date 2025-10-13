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
        private(set) var attributes: Attributes
        private(set) var events: [(name: String, attributes: Attributes?)] = []
        private(set) var status: SpanStatus?
        private let context: SpanContext

        init(name: String, attributes: Attributes?) {
            self.name = name
            self.attributes = attributes ?? [:]
            self.context = SpanContext(traceId: "test-trace-id", spanId: "test-span-id", traceFlags: 0)
        }

        func spanContext() -> SpanContext {
            context
        }

        @discardableResult
        func setAttribute(_ key: String, value: AttributeValue) -> Self {
            attributes[key] = value
            return self
        }

        @discardableResult
        func setAttributes(_ attributes: Attributes) -> Self {
            for (key, value) in attributes {
                self.attributes[key] = value
            }
            return self
        }

        @discardableResult
        func addEvent(_ name: String, attributes: Attributes?) -> Self {
            events.append((name: name, attributes: attributes))
            return self
        }

        @discardableResult
        func setStatus(_ status: SpanStatus) -> Self {
            self.status = status
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
            events.append((name: "exception", attributes: attributes))
            return self
        }
    }

    private(set) var spans: [MockSpan] = []

    var spanRecords: [SpanRecord] {
        spans.map { span in
            SpanRecord(
                name: span.name,
                attributes: span.attributes,
                events: span.events.map { event in SpanEvent(name: event.name, attributes: event.attributes) },
                status: span.status.map { SpanStatusRecord(code: $0.code, message: $0.message) }
            )
        }
    }

    func startSpan(name: String, options: SpanOptions?) -> any Span {
        let span = MockSpan(name: name, attributes: options?.attributes)
        spans.append(span)
        return span
    }

    func startActiveSpan<T>(
        _ name: String,
        options: SpanOptions?,
        _ fn: @Sendable (any Span) async throws -> T
    ) async rethrows -> T {
        let span = MockSpan(name: name, attributes: options?.attributes)
        spans.append(span)
        return try await fn(span)
    }
}
