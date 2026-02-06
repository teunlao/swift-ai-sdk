import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Get base telemetry attributes from model, settings, and metadata.

 Port of `@ai-sdk/ai/src/telemetry/get-base-telemetry-attributes.ts`.

 Assembles core telemetry attributes from:
 - Model provider and ID
 - Call settings (excluding abortSignal, headers, temperature)
 - Telemetry metadata
 - Request headers
 */

/// Model info for telemetry
public struct TelemetryModelInfo: Sendable {
    public let modelId: String
    public let provider: String

    public init(modelId: String, provider: String) {
        self.modelId = modelId
        self.provider = provider
    }
}

/// Get base telemetry attributes
///
/// - Parameters:
///   - model: Model information (provider and ID)
///   - settings: Call settings (generation parameters)
///   - telemetry: Telemetry configuration
///   - headers: Request headers
/// - Returns: Attributes dictionary with model info, settings, metadata, and headers
public func getBaseTelemetryAttributes(
    model: TelemetryModelInfo,
    settings: CallSettings,
    telemetry: TelemetrySettings?,
    headers: [String: String]?
) -> Attributes {
    var attributes: Attributes = [:]

    // Model info
    attributes["ai.model.provider"] = .string(model.provider)
    attributes["ai.model.id"] = .string(model.modelId)

    // Settings (excluding abortSignal and headers per upstream)
    if let maxOutputTokens = settings.maxOutputTokens {
        attributes["ai.settings.maxOutputTokens"] = .int(maxOutputTokens)
    }
    if let topP = settings.topP {
        attributes["ai.settings.topP"] = .double(topP)
    }
    if let topK = settings.topK {
        attributes["ai.settings.topK"] = .int(topK)
    }
    if let presencePenalty = settings.presencePenalty {
        attributes["ai.settings.presencePenalty"] = .double(presencePenalty)
    }
    if let frequencyPenalty = settings.frequencyPenalty {
        attributes["ai.settings.frequencyPenalty"] = .double(frequencyPenalty)
    }
    if let stopSequences = settings.stopSequences {
        attributes["ai.settings.stopSequences"] = .stringArray(stopSequences)
    }
    if let seed = settings.seed {
        attributes["ai.settings.seed"] = .int(seed)
    }
    if let maxRetries = settings.maxRetries {
        attributes["ai.settings.maxRetries"] = .int(maxRetries)
    }
    if let timeout = settings.timeout, let totalTimeoutMs = getTotalTimeoutMs(timeout) {
        attributes["ai.settings.timeout"] = .int(totalTimeoutMs)
    }
    // abortSignal and headers are intentionally excluded (per upstream)

    // Add metadata as attributes
    if let metadata = telemetry?.metadata {
        for (key, value) in metadata {
            attributes["ai.telemetry.metadata.\(key)"] = value
        }
    }

    // Request headers
    if let headers = headers {
        for (key, value) in headers {
            attributes["ai.request.headers.\(key)"] = .string(value)
        }
    }

    return attributes
}
