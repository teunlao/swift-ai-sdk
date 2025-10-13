import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Select telemetry attributes based on recording settings.

 Port of `@ai-sdk/ai/src/telemetry/select-telemetry-attributes.ts`.

 Filters attributes based on telemetry configuration:
 - If telemetry is disabled: returns empty dictionary
 - Input attributes: included only if recordInputs is enabled (default: true)
 - Output attributes: included only if recordOutputs is enabled (default: true)
 - Regular attributes: always included
 */

/// Resolvable attribute value (can be computed lazily)
public enum ResolvableAttributeValue: Sendable {
    /// Regular attribute value (always included)
    case value(AttributeValue)

    /// Input attribute (included only if recordInputs is enabled)
    case input(@Sendable () async throws -> AttributeValue?)

    /// Output attribute (included only if recordOutputs is enabled)
    case output(@Sendable () async throws -> AttributeValue?)
}

/// Select telemetry attributes based on settings
///
/// - Parameters:
///   - telemetry: Telemetry configuration
///   - attributes: Attributes to filter (with resolvable values)
/// - Returns: Filtered attributes dictionary
public func selectTelemetryAttributes(
    telemetry: TelemetrySettings?,
    attributes: [String: ResolvableAttributeValue?]
) async throws -> Attributes {
    // When telemetry is disabled, return empty object to avoid serialization overhead
    guard telemetry?.isEnabled == true else {
        return [:]
    }

    var resultAttributes: Attributes = [:]

    for (key, valueWrapper) in attributes {
        guard let valueWrapper = valueWrapper else {
            continue
        }

        switch valueWrapper {
        case .value(let attributeValue):
            // Regular value - always include
            resultAttributes[key] = attributeValue

        case .input(let inputFn):
            // Input value - check if should be recorded (default to true)
            if telemetry?.recordInputs == false {
                continue
            }

            if let result = try await inputFn() {
                resultAttributes[key] = result
            }

        case .output(let outputFn):
            // Output value - check if should be recorded (default to true)
            if telemetry?.recordOutputs == false {
                continue
            }

            if let result = try await outputFn() {
                resultAttributes[key] = result
            }
        }
    }

    return resultAttributes
}
