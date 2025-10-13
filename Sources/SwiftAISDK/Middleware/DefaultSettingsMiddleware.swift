/**
 Applies default settings for a language model.

 Port of `@ai-sdk/ai/src/middleware/default-settings-middleware.ts`.

 This middleware allows you to specify default values for various language model
 settings. User-provided settings will take precedence over these defaults, with
 deep merging for nested objects like `providerOptions` and `headers`.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Creates a middleware that applies default settings to language model calls.
///
/// The middleware performs deep merging of settings, meaning:
/// - Scalar values (temperature, maxOutputTokens, etc.) are replaced by user values if provided
/// - Nested objects (providerOptions, headers) are deeply merged, allowing partial overrides
/// - Arrays are replaced entirely, not merged
///
/// - Parameter settings: Default settings to apply
/// - Returns: A middleware that merges these defaults with user-provided settings
public func defaultSettingsMiddleware(
    settings: DefaultSettings
) -> LanguageModelV3Middleware {
    LanguageModelV3Middleware(
        transformParams: { type, params, model in
            // Convert settings struct to dictionary for merging
            let settingsDict = settings.toDictionary()

            // Convert params to dictionary
            let paramsDict = params.toDictionary()

            // Merge settings (base) with params (overrides)
            // User-provided params take precedence
            guard let merged = mergeObjects(settingsDict, paramsDict) else {
                return params
            }

            // Convert back to LanguageModelV3CallOptions
            return LanguageModelV3CallOptions.fromDictionary(merged)
        }
    )
}

/// Default settings that can be applied to language model calls.
///
/// All fields are optional. When specified, they will be used as defaults
/// unless overridden by the user at call time.
public struct DefaultSettings: Sendable {
    public let maxOutputTokens: Int?
    public let temperature: Double?
    public let stopSequences: [String]?
    public let topP: Double?
    public let topK: Int?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?
    public let responseFormat: LanguageModelV3ResponseFormat?
    public let seed: Int?
    public let tools: [LanguageModelV3Tool]?
    public let toolChoice: LanguageModelV3ToolChoice?
    public let headers: [String: String]?
    public let providerOptions: SharedV3ProviderOptions?

    public init(
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        stopSequences: [String]? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        responseFormat: LanguageModelV3ResponseFormat? = nil,
        seed: Int? = nil,
        tools: [LanguageModelV3Tool]? = nil,
        toolChoice: LanguageModelV3ToolChoice? = nil,
        headers: [String: String]? = nil,
        providerOptions: SharedV3ProviderOptions? = nil
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.stopSequences = stopSequences
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.responseFormat = responseFormat
        self.seed = seed
        self.tools = tools
        self.toolChoice = toolChoice
        self.headers = headers
        self.providerOptions = providerOptions
    }

    /// Converts settings to a dictionary for merging.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        if let value = maxOutputTokens { dict["maxOutputTokens"] = value }
        if let value = temperature { dict["temperature"] = value }
        if let value = stopSequences { dict["stopSequences"] = value }
        if let value = topP { dict["topP"] = value }
        if let value = topK { dict["topK"] = value }
        if let value = presencePenalty { dict["presencePenalty"] = value }
        if let value = frequencyPenalty { dict["frequencyPenalty"] = value }
        if let value = responseFormat { dict["responseFormat"] = value }
        if let value = seed { dict["seed"] = value }
        if let value = tools { dict["tools"] = value }
        if let value = toolChoice { dict["toolChoice"] = value }
        if let value = headers { dict["headers"] = value }
        if let value = providerOptions { dict["providerOptions"] = value }

        return dict
    }
}

// MARK: - LanguageModelV3CallOptions Dictionary Conversion

extension LanguageModelV3CallOptions {
    /// Converts call options to a dictionary for merging.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        // Always include prompt
        dict["prompt"] = prompt

        // Optional parameters
        if let value = maxOutputTokens { dict["maxOutputTokens"] = value }
        if let value = temperature { dict["temperature"] = value }
        if let value = stopSequences { dict["stopSequences"] = value }
        if let value = topP { dict["topP"] = value }
        if let value = topK { dict["topK"] = value }
        if let value = presencePenalty { dict["presencePenalty"] = value }
        if let value = frequencyPenalty { dict["frequencyPenalty"] = value }
        if let value = responseFormat { dict["responseFormat"] = value }
        if let value = seed { dict["seed"] = value }
        if let value = tools { dict["tools"] = value }
        if let value = toolChoice { dict["toolChoice"] = value }
        if let value = includeRawChunks { dict["includeRawChunks"] = value }
        if let value = abortSignal { dict["abortSignal"] = value }
        if let value = headers { dict["headers"] = value }
        if let value = providerOptions { dict["providerOptions"] = value }

        return dict
    }

    /// Creates call options from a merged dictionary.
    static func fromDictionary(_ dict: [String: Any]) -> LanguageModelV3CallOptions {
        LanguageModelV3CallOptions(
            prompt: dict["prompt"] as! LanguageModelV3Prompt,
            maxOutputTokens: dict["maxOutputTokens"] as? Int,
            temperature: dict["temperature"] as? Double,
            stopSequences: dict["stopSequences"] as? [String],
            topP: dict["topP"] as? Double,
            topK: dict["topK"] as? Int,
            presencePenalty: dict["presencePenalty"] as? Double,
            frequencyPenalty: dict["frequencyPenalty"] as? Double,
            responseFormat: dict["responseFormat"] as? LanguageModelV3ResponseFormat,
            seed: dict["seed"] as? Int,
            tools: dict["tools"] as? [LanguageModelV3Tool],
            toolChoice: dict["toolChoice"] as? LanguageModelV3ToolChoice,
            includeRawChunks: dict["includeRawChunks"] as? Bool,
            abortSignal: dict["abortSignal"] as? (@Sendable () -> Bool),
            headers: dict["headers"] as? [String: String],
            providerOptions: dict["providerOptions"] as? SharedV3ProviderOptions
        )
    }
}
