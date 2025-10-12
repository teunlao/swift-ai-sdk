/**
 Record an OpenTelemetry span with automatic error handling.

 Port of `@ai-sdk/ai/src/telemetry/record-span.ts`.

 This function:
 1. Starts an active span with given attributes
 2. Executes a function within the span context
 3. Handles errors by recording them on the span
 4. Automatically ends the span when done (unless disabled)
 */

import Foundation

/// Record a span and execute a function within its context
///
/// - Parameters:
///   - name: Span name
///   - tracer: Tracer to use for creating the span
///   - attributes: Attributes to attach to the span (can be async)
///   - fn: Function to execute within span context
///   - endWhenDone: Whether to end span after function completes (default: true)
/// - Returns: Result of the function
/// - Throws: Any error thrown by the function
public func recordSpan<T>(
    name: String,
    tracer: any Tracer,
    attributes: Attributes,
    fn: @Sendable (any Span) async throws -> T,
    endWhenDone: Bool = true
) async rethrows -> T {
    // Note: TypeScript version supports async attributes (Promise<Attributes>)
    // Swift version receives resolved attributes directly for simplicity
    return try await tracer.startActiveSpan(
        name,
        options: SpanOptions(attributes: attributes),
        { span in
            do {
                let result = try await fn(span)

                if endWhenDone {
                    span.end()
                }

                return result
            } catch {
                // Record error on span
                recordErrorOnSpan(span, error: error)

                // Always stop the span when there is an error
                span.end()

                throw error
            }
        }
    )
}

/// Record an error on a span
///
/// If the error is an instance of Error, an exception event will be recorded on the span.
/// Otherwise, the span will be set to an error status.
///
/// - Parameters:
///   - span: The span to record the error on
///   - error: The error to record on the span
public func recordErrorOnSpan(_ span: any Span, error: Error) {
    // Record exception with Swift error details
    let nsError = error as NSError

    span.recordException(
        ExceptionEvent(
            name: String(describing: type(of: error)),
            message: nsError.localizedDescription,
            stack: Thread.callStackSymbols.joined(separator: "\n")
        )
    )

    span.setStatus(
        SpanStatus(
            code: .error,
            message: nsError.localizedDescription
        )
    )
}
