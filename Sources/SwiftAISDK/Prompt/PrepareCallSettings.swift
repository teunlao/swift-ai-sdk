import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Result of preparing call settings (omits abortSignal, headers, maxRetries).

 Port of `@ai-sdk/ai/src/prompt/prepare-call-settings.ts` return type.
 */
public struct PreparedCallSettings: Sendable, Equatable {
    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var stopSequences: [String]?
    public var seed: Int?

    public init(
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.stopSequences = stopSequences
        self.seed = seed
    }
}

/**
 Validates call settings and returns a new object with limited values.

 Port of `@ai-sdk/ai/src/prompt/prepare-call-settings.ts::prepareCallSettings`.

 - Parameters:
   - maxOutputTokens: Maximum number of tokens to generate (must be >= 1 if provided)
   - temperature: Temperature setting for randomness
   - topP: Nucleus sampling parameter
   - topK: Top-K sampling parameter
   - presencePenalty: Presence penalty setting
   - frequencyPenalty: Frequency penalty setting
   - stopSequences: Stop sequences
   - seed: Random seed for deterministic sampling

 - Throws: `InvalidArgumentError` if validation fails

 - Returns: A `PreparedCallSettings` with validated values

 ## Note
 Swift's type system eliminates many runtime type checks from the TypeScript version:
 - `temperature`, `topP`, etc. are guaranteed to be numbers by Swift's type system
 - Only business logic validation (e.g., maxOutputTokens >= 1) is needed
 */
public func prepareCallSettings(
    maxOutputTokens: Int? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    presencePenalty: Double? = nil,
    frequencyPenalty: Double? = nil,
    stopSequences: [String]? = nil,
    seed: Int? = nil
) throws -> PreparedCallSettings {
    // Validate maxOutputTokens
    if let maxOutputTokens = maxOutputTokens {
        if maxOutputTokens < 1 {
            throw InvalidArgumentError(
                parameter: "maxOutputTokens",
                value: .number(Double(maxOutputTokens)),
                message: "maxOutputTokens must be >= 1"
            )
        }
    }

    // Swift's type system guarantees that temperature, topP, topK,
    // presencePenalty, frequencyPenalty, and seed are the correct types,
    // so no additional validation is needed beyond what TypeScript does

    // Return validated settings
    return PreparedCallSettings(
        maxOutputTokens: maxOutputTokens,
        temperature: temperature,
        topP: topP,
        topK: topK,
        presencePenalty: presencePenalty,
        frequencyPenalty: frequencyPenalty,
        stopSequences: stopSequences,
        seed: seed
    )
}
