/**
 OpenTelemetry Tracer protocol.

 Minimal abstraction of OpenTelemetry API types for telemetry support.
 Port of `@opentelemetry/api` Tracer interface.

 This allows telemetry functionality without requiring OpenTelemetry SDK dependency.
 Users can bridge these to real OpenTelemetry types if needed.
 */

/// Span options for starting a span
public struct SpanOptions: Sendable {
    public let attributes: Attributes?

    public init(attributes: Attributes? = nil) {
        self.attributes = attributes
    }
}

/// OpenTelemetry Tracer protocol
public protocol Tracer: Sendable {
    /// Start a new span
    func startSpan(name: String, options: SpanOptions?) -> any Span

    /// Start an active span and execute a function within its context
    func startActiveSpan<T>(
        _ name: String,
        options: SpanOptions?,
        _ fn: @Sendable (any Span) async throws -> T
    ) async rethrows -> T
}

// MARK: - Default Implementations

extension Tracer {
    public func startSpan(name: String) -> any Span {
        startSpan(name: name, options: nil)
    }

    public func startActiveSpan<T>(
        _ name: String,
        _ fn: @Sendable (any Span) async throws -> T
    ) async rethrows -> T {
        try await startActiveSpan(name, options: nil, fn)
    }
}
