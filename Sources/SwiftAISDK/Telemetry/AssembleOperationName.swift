import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Assemble standardized operation name and attributes for telemetry.

 Port of `@ai-sdk/ai/src/telemetry/assemble-operation-name.ts`.

 Combines operation ID with optional function ID to create standardized
 telemetry attributes following OpenTelemetry conventions.
 */

/// Assemble operation name and related attributes
///
/// - Parameters:
///   - operationId: The operation identifier (e.g., "ai.generateText")
///   - telemetry: Telemetry settings (optional)
/// - Returns: Attributes dictionary with operation name and resource name
public func assembleOperationName(
    operationId: String,
    telemetry: TelemetrySettings?
) -> Attributes {
    var attributes: Attributes = [:]

    // Standardized operation and resource name
    let operationName: String
    if let functionId = telemetry?.functionId {
        operationName = "\(operationId) \(functionId)"
    } else {
        operationName = operationId
    }

    attributes["operation.name"] = .string(operationName)

    if let functionId = telemetry?.functionId {
        attributes["resource.name"] = .string(functionId)
    }

    // Detailed, AI SDK specific data
    attributes["ai.operationId"] = .string(operationId)

    if let functionId = telemetry?.functionId {
        attributes["ai.telemetry.functionId"] = .string(functionId)
    }

    return attributes
}
