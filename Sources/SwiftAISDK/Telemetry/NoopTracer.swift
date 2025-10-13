import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Tracer implementation that does nothing (null object pattern).

 Port of `@ai-sdk/ai/src/telemetry/noop-tracer.ts`.

 Used when telemetry is disabled to avoid overhead of real tracing.
 */

/// Noop span context (empty trace/span IDs)
private let noopSpanContext = SpanContext(
    traceId: "",
    spanId: "",
    traceFlags: 0
)

/// Noop span implementation (does nothing)
private final class NoopSpan: Span, @unchecked Sendable {
    func spanContext() -> SpanContext {
        return noopSpanContext
    }

    @discardableResult
    func setAttribute(_ key: String, value: AttributeValue) -> Self {
        return self
    }

    @discardableResult
    func setAttributes(_ attributes: Attributes) -> Self {
        return self
    }

    @discardableResult
    func addEvent(_ name: String, attributes: Attributes?) -> Self {
        return self
    }

    @discardableResult
    func setStatus(_ status: SpanStatus) -> Self {
        return self
    }

    @discardableResult
    func updateName(_ name: String) -> Self {
        return self
    }

    func end() {
        // Do nothing
    }

    func isRecording() -> Bool {
        return false
    }

    @discardableResult
    func recordException(_ exception: ExceptionEvent) -> Self {
        return self
    }
}

/// Shared noop span instance
private let noopSpan: any Span = NoopSpan()

/// Noop tracer implementation (does nothing)
public final class NoopTracer: Tracer, @unchecked Sendable {
    public func startSpan(name: String, options: SpanOptions?) -> any Span {
        return noopSpan
    }

    public func startActiveSpan<T>(
        _ name: String,
        options: SpanOptions?,
        _ fn: @Sendable (any Span) async throws -> T
    ) async rethrows -> T {
        return try await fn(noopSpan)
    }
}

/// Shared noop tracer instance
public let noopTracer: any Tracer = NoopTracer()
