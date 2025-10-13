import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 OpenTelemetry Span protocol.

 Minimal abstraction of OpenTelemetry API types for telemetry support.
 Port of `@opentelemetry/api` Span interface.

 This allows telemetry functionality without requiring OpenTelemetry SDK dependency.
 Users can bridge these to real OpenTelemetry types if needed.
 */

/// Status code for span
public enum SpanStatusCode: Sendable {
    case unset
    case ok
    case error
}

/// Span status
public struct SpanStatus: Sendable {
    public let code: SpanStatusCode
    public let message: String?

    public init(code: SpanStatusCode, message: String? = nil) {
        self.code = code
        self.message = message
    }
}

/// Span context (trace/span IDs and flags)
public struct SpanContext: Sendable {
    public let traceId: String
    public let spanId: String
    public let traceFlags: Int

    public init(traceId: String, spanId: String, traceFlags: Int) {
        self.traceId = traceId
        self.spanId = spanId
        self.traceFlags = traceFlags
    }
}

/// Exception event data
public struct ExceptionEvent: Sendable {
    public let name: String?
    public let message: String?
    public let stack: String?

    public init(name: String? = nil, message: String? = nil, stack: String? = nil) {
        self.name = name
        self.message = message
        self.stack = stack
    }
}

/// OpenTelemetry Span protocol
public protocol Span: Sendable {
    /// Get span context
    func spanContext() -> SpanContext

    /// Set single attribute
    @discardableResult
    func setAttribute(_ key: String, value: AttributeValue) -> Self

    /// Set multiple attributes
    @discardableResult
    func setAttributes(_ attributes: Attributes) -> Self

    /// Add event
    @discardableResult
    func addEvent(_ name: String, attributes: Attributes?) -> Self

    /// Set span status
    @discardableResult
    func setStatus(_ status: SpanStatus) -> Self

    /// Update span name
    @discardableResult
    func updateName(_ name: String) -> Self

    /// End span
    func end()

    /// Check if span is recording
    func isRecording() -> Bool

    /// Record exception
    @discardableResult
    func recordException(_ exception: ExceptionEvent) -> Self
}
