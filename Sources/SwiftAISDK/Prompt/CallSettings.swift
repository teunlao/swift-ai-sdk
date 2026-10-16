import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Timeout configuration for API calls: a total timeout in milliseconds, or
 granular timeouts.

 Port of `TimeoutConfiguration` from `@ai-sdk/ai/src/prompt/request-options.ts`.
 Upstream keys per-tool timeouts as `<toolName>Ms`; `tools` here is keyed by the
 tool name itself.
 */
public enum TimeoutConfiguration: Sendable, Equatable, ExpressibleByIntegerLiteral {
    /// A timeout value in milliseconds (equivalent to `totalMs`).
    case milliseconds(Int)
    /// Granular timeout configuration in milliseconds.
    case configuration(
        totalMs: Int? = nil,
        stepMs: Int? = nil,
        firstChunkMs: Int? = nil,
        chunkMs: Int? = nil,
        toolMs: Int? = nil,
        tools: [String: Int]? = nil
    )

    public init(integerLiteral value: Int) {
        self = .milliseconds(value)
    }

    public static func totalMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(totalMs: value)
    }

    public static func stepMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(stepMs: value)
    }

    public static func firstChunkMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(firstChunkMs: value)
    }

    public static func chunkMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(chunkMs: value)
    }

    public static func toolMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(toolMs: value)
    }
}

/// Port of `getTotalTimeoutMs` from `@ai-sdk/ai/src/prompt/request-options.ts`.
public func getTotalTimeoutMs(_ timeout: TimeoutConfiguration?) -> Int? {
    switch timeout {
    case .milliseconds(let value):
        return value
    case .configuration(let totalMs, _, _, _, _, _):
        return totalMs
    case nil:
        return nil
    }
}

/// Port of `getStepTimeoutMs` from `@ai-sdk/ai/src/prompt/request-options.ts`.
public func getStepTimeoutMs(_ timeout: TimeoutConfiguration?) -> Int? {
    if case .configuration(_, let stepMs, _, _, _, _) = timeout { return stepMs }
    return nil
}

/// Port of `getFirstChunkTimeoutMs` from `@ai-sdk/ai/src/prompt/request-options.ts`.
public func getFirstChunkTimeoutMs(_ timeout: TimeoutConfiguration?) -> Int? {
    if case .configuration(_, _, let firstChunkMs, _, _, _) = timeout { return firstChunkMs }
    return nil
}

/// Port of `getChunkTimeoutMs` from `@ai-sdk/ai/src/prompt/request-options.ts`.
public func getChunkTimeoutMs(_ timeout: TimeoutConfiguration?) -> Int? {
    if case .configuration(_, _, _, let chunkMs, _, _) = timeout { return chunkMs }
    return nil
}

/// Port of `getToolTimeoutMs` from `@ai-sdk/ai/src/prompt/request-options.ts`.
public func getToolTimeoutMs(_ timeout: TimeoutConfiguration?, toolName: String) -> Int? {
    if case .configuration(_, _, _, _, let toolMs, let tools) = timeout {
        return tools?[toolName] ?? toolMs
    }
    return nil
}

/**
 Language model call options shared by generation functions and step overrides.

 Port of `@ai-sdk/ai/src/prompt/language-model-call-options.ts`.
 */
public struct LanguageModelCallOptions: Sendable, Equatable {
    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var stopSequences: [String]?
    public var seed: Int?
    public var reasoning: LanguageModelV4ReasoningEffort?

    public init(
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil,
        reasoning: LanguageModelV4ReasoningEffort? = nil
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.stopSequences = stopSequences
        self.seed = seed
        self.reasoning = reasoning
    }

    /**
     Validates the options.

     Port of `@ai-sdk/ai/src/prompt/prepare-language-model-call-options.ts`;
     Swift types already guarantee the numeric kinds.
     */
    public func prepared() throws -> LanguageModelCallOptions {
        if let maxOutputTokens, maxOutputTokens < 1 {
            throw InvalidArgumentError(
                parameter: "maxOutputTokens",
                value: .number(Double(maxOutputTokens)),
                message: "maxOutputTokens must be >= 1"
            )
        }
        return self
    }

    /**
     Step settings layered over the call settings.

     Port of `@ai-sdk/ai/src/generate-text/prepare-step-call-settings.ts`.
     */
    public func overridden(by step: LanguageModelCallOptions?) throws -> LanguageModelCallOptions {
        try LanguageModelCallOptions(
            maxOutputTokens: step?.maxOutputTokens ?? maxOutputTokens,
            temperature: step?.temperature ?? temperature,
            topP: step?.topP ?? topP,
            topK: step?.topK ?? topK,
            presencePenalty: step?.presencePenalty ?? presencePenalty,
            frequencyPenalty: step?.frequencyPenalty ?? frequencyPenalty,
            stopSequences: step?.stopSequences ?? stopSequences,
            seed: step?.seed ?? seed,
            reasoning: step?.reasoning ?? reasoning
        ).prepared()
    }
}

/**
 Settings for AI model calls (generation parameters).

 Port of `@ai-sdk/ai/src/prompt/call-settings.ts`.

 These settings control the behavior of the language model during text generation.

 ## Example
 ```swift
 let settings = CallSettings(
     maxOutputTokens: 1000,
     temperature: 0.7,
     topP: 0.9,
     stopSequences: ["END"],
     maxRetries: 3
 )
 ```
 */
public struct CallSettings: Sendable, Equatable {
    /**
     Maximum number of tokens to generate.

     The exact interpretation depends on the model and provider.
     */
    public var maxOutputTokens: Int?

    /**
     Temperature setting for randomness.

     The range depends on the provider and model. Typically 0-2, where:
     - 0 = deterministic/focused
     - Higher values = more random/creative

     **Note**: It's recommended to set either `temperature` or `topP`, but not both.
     */
    public var temperature: Double?

    /**
     Nucleus sampling (top-p) parameter.

     A number between 0 and 1. For example, 0.1 means only tokens with the
     top 10% probability mass are considered.

     **Note**: It's recommended to set either `temperature` or `topP`, but not both.
     */
    public var topP: Double?

    /**
     Top-K sampling parameter.

     Only sample from the top K options for each subsequent token.

     Used to remove "long tail" low probability responses.
     **Recommended for advanced use cases only**. You usually only need `temperature`.
     */
    public var topK: Int?

    /**
     Presence penalty setting.

     Affects the likelihood of the model to repeat information already in the prompt.

     Range: -1 (increase repetition) to 1 (maximum penalty, decrease repetition).
     0 means no penalty.
     */
    public var presencePenalty: Double?

    /**
     Frequency penalty setting.

     Affects the likelihood of the model to repeatedly use the same words or phrases.

     Range: -1 (increase repetition) to 1 (maximum penalty, decrease repetition).
     0 means no penalty.
     */
    public var frequencyPenalty: Double?

    /**
     Stop sequences.

     If set, the model will stop generating text when one of the stop sequences is generated.
     Providers may have limits on the number of stop sequences.
     */
    public var stopSequences: [String]?

    /**
     Random seed for deterministic sampling.

     If set and supported by the model, calls will generate deterministic results.
     */
    public var seed: Int?

    /**
     Reasoning effort level for V4 language models.

     Use `.providerDefault` to delegate to the provider default, or `.none` to
     disable reasoning when supported by the provider.
     */
    public var reasoning: LanguageModelV4ReasoningEffort?

    /**
     Maximum number of retries for failed requests.

     Set to 0 to disable retries. Default is 2.
     */
    public var maxRetries: Int?

    /**
     Cancellation handler.

     Swift equivalent of JavaScript's `AbortSignal`. Use `@Sendable () -> Bool`
     to check if the operation should be cancelled.

     ## Example
     ```swift
     var cancelled = false
     let settings = CallSettings(
         abortSignal: { cancelled }
     )
     // Later: cancelled = true
     ```
     */
    public var abortSignal: (@Sendable () -> Bool)?

    /**
     Timeout in milliseconds. The call will be aborted if it takes longer
     than the specified timeout. Can be used alongside abortSignal.

     Equivalent to TypeScript's `TimeoutConfiguration`.
     */
    public var timeout: TimeoutConfiguration?

    /**
     Additional HTTP headers to send with the request.

     Only applicable for HTTP-based providers.
     */
    public var headers: [String: String]?

    public init(
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil,
        reasoning: LanguageModelV4ReasoningEffort? = nil,
        maxRetries: Int? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        timeout: TimeoutConfiguration? = nil,
        headers: [String: String]? = nil
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.stopSequences = stopSequences
        self.seed = seed
        self.reasoning = reasoning
        self.maxRetries = maxRetries
        self.abortSignal = abortSignal
        self.timeout = timeout
        self.headers = headers
    }
}

// MARK: - Equatable Conformance

extension CallSettings {
    /**
     Equatable conformance for CallSettings.

     Note: `abortSignal` is intentionally excluded from comparison.

     **Reason**: Swift closures are not Equatable by default. Comparing function
     pointers would require `ObjectIdentifier`, but that has unclear semantics
     (two different closures with identical behavior would not be equal).

     **TypeScript comparison**: In TypeScript, CallSettings is a type alias (not a class),
     so equality comparison is rarely used. The XOR constraint (abortSignal vs no signal)
     is the primary concern, which is handled at the type level in Swift.

     This is an acceptable deviation from 100% parity since:
     1. Equality of cancellation handlers is not semantically meaningful
     2. CallSettings is primarily used for configuration, not value comparison
     3. All other fields participate in equality checks
     */
    public static func == (lhs: CallSettings, rhs: CallSettings) -> Bool {
        return lhs.maxOutputTokens == rhs.maxOutputTokens &&
            lhs.temperature == rhs.temperature &&
            lhs.topP == rhs.topP &&
            lhs.topK == rhs.topK &&
            lhs.presencePenalty == rhs.presencePenalty &&
            lhs.frequencyPenalty == rhs.frequencyPenalty &&
            lhs.stopSequences == rhs.stopSequences &&
            lhs.seed == rhs.seed &&
            lhs.reasoning == rhs.reasoning &&
            lhs.maxRetries == rhs.maxRetries &&
            lhs.timeout == rhs.timeout &&
            lhs.headers == rhs.headers
        // abortSignal excluded (see doc comment above)
    }
}
