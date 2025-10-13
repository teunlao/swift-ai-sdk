import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Get a tracer for telemetry.

 Port of `@ai-sdk/ai/src/telemetry/get-tracer.ts`.

 Returns appropriate tracer based on telemetry configuration:
 - If disabled: returns noopTracer
 - If custom tracer provided: returns custom tracer
 - Otherwise: returns default tracer (currently noop, can be customized)
 */

/// Global default tracer (optional, can be set by user)
///
/// In TypeScript, this uses `trace.getTracer('ai')` from OpenTelemetry API.
/// In Swift, we default to noop but allow users to set a custom tracer.
///
/// Example:
/// ```swift
/// import SwiftOpenTelemetry
/// globalDefaultTelemetryTracer = MyOpenTelemetryTracer()
/// ```
///
/// **Thread Safety**: Marked `nonisolated(unsafe)` to match JavaScript's
/// global mutable state. Users are responsible for synchronization if
/// mutating from multiple threads.
nonisolated(unsafe) public var globalDefaultTelemetryTracer: (any Tracer)? = nil

/// Get tracer for telemetry
///
/// - Parameters:
///   - isEnabled: Whether telemetry is enabled (default: false)
///   - tracer: Custom tracer to use (optional)
/// - Returns: Appropriate tracer based on configuration
public func getTracer(
    isEnabled: Bool = false,
    tracer: (any Tracer)? = nil
) -> any Tracer {
    if !isEnabled {
        return noopTracer
    }

    if let customTracer = tracer {
        return customTracer
    }

    // Use global default tracer if set, otherwise noop
    return globalDefaultTelemetryTracer ?? noopTracer
}
