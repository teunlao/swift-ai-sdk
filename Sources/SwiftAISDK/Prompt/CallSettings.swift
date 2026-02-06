import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Timeout configuration for API calls. Can be specified as:
 - An integer representing milliseconds
 - A configuration object with `totalMs`, `stepMs`, and/or `chunkMs` fields

 Port of `@ai-sdk/ai/src/prompt/call-settings.ts` `TimeoutConfiguration`.
 */
public enum TimeoutConfiguration: Sendable, Equatable, ExpressibleByIntegerLiteral {
    /// A timeout value in milliseconds (equivalent to `totalMs`).
    case milliseconds(Int)
    /// Granular timeout configuration in milliseconds.
    case configuration(totalMs: Int? = nil, stepMs: Int? = nil, chunkMs: Int? = nil)

    public init(integerLiteral value: Int) {
        self = .milliseconds(value)
    }

    public static func totalMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(totalMs: value)
    }

    public static func stepMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(stepMs: value)
    }

    public static func chunkMs(_ value: Int) -> TimeoutConfiguration {
        .configuration(chunkMs: value)
    }
}

/**
 Extracts the total timeout value in milliseconds from a TimeoutConfiguration.

 Port of `@ai-sdk/ai/src/prompt/call-settings.ts::getTotalTimeoutMs`.
 */
public func getTotalTimeoutMs(_ timeout: TimeoutConfiguration?) -> Int? {
    guard let timeout else { return nil }
    switch timeout {
    case .milliseconds(let value):
        return value
    case .configuration(let totalMs, _, _):
        return totalMs
    }
}

/**
 Extracts the step timeout value in milliseconds from a TimeoutConfiguration.

 Port of `@ai-sdk/ai/src/prompt/call-settings.ts::getStepTimeoutMs`.
 */
public func getStepTimeoutMs(_ timeout: TimeoutConfiguration?) -> Int? {
    guard let timeout else { return nil }
    switch timeout {
    case .milliseconds:
        return nil
    case .configuration(_, let stepMs, _):
        return stepMs
    }
}

/**
 Extracts the chunk timeout value in milliseconds from a TimeoutConfiguration.

 Port of `@ai-sdk/ai/src/prompt/call-settings.ts::getChunkTimeoutMs`.
 */
public func getChunkTimeoutMs(_ timeout: TimeoutConfiguration?) -> Int? {
    guard let timeout else { return nil }
    switch timeout {
    case .milliseconds:
        return nil
    case .configuration(_, _, let chunkMs):
        return chunkMs
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
            lhs.maxRetries == rhs.maxRetries &&
            lhs.timeout == rhs.timeout &&
            lhs.headers == rhs.headers
        // abortSignal excluded (see doc comment above)
    }
}
