import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum OpenAIChatLogprobsOption: Sendable, Equatable {
    case bool(Bool)
    case number(Double)

    var jsonValue: JSONValue {
        switch self {
        case .bool(let flag):
            return .bool(flag)
        case .number(let value):
            return .number(value)
        }
    }
}

public enum OpenAIChatReasoningEffort: String, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public enum OpenAIChatServiceTier: String, Sendable {
    case auto
    case flex
    case priority
    case `default`
}

public enum OpenAIChatTextVerbosity: String, Sendable {
    case low
    case medium
    case high
}

public enum OpenAIChatSystemMessageMode: Sendable, Equatable {
    case system
    case developer
    case remove
}

public enum OpenAIChatPromptCacheRetention: String, Sendable {
    case inMemory = "in_memory"
    case twentyFourHours = "24h"
}

public struct OpenAIChatProviderOptions: Sendable, Equatable {
    public var logitBias: [String: Double]?
    public var logprobs: OpenAIChatLogprobsOption?
    public var parallelToolCalls: Bool?
    public var user: String?
    public var reasoningEffort: OpenAIChatReasoningEffort?
    public var maxCompletionTokens: Double?
    public var store: Bool?
    public var metadata: [String: String]?
    public var prediction: [String: JSONValue]?
    public var serviceTier: OpenAIChatServiceTier?
    public var strictJsonSchema: Bool?
    public var textVerbosity: OpenAIChatTextVerbosity?
    public var promptCacheKey: String?
    public var promptCacheRetention: OpenAIChatPromptCacheRetention?
    public var safetyIdentifier: String?
    public var systemMessageMode: OpenAIChatSystemMessageMode?
    public var forceReasoning: Bool?

    public init(
        logitBias: [String: Double]? = nil,
        logprobs: OpenAIChatLogprobsOption? = nil,
        parallelToolCalls: Bool? = nil,
        user: String? = nil,
        reasoningEffort: OpenAIChatReasoningEffort? = nil,
        maxCompletionTokens: Double? = nil,
        store: Bool? = nil,
        metadata: [String: String]? = nil,
        prediction: [String: JSONValue]? = nil,
        serviceTier: OpenAIChatServiceTier? = nil,
        strictJsonSchema: Bool? = nil,
        textVerbosity: OpenAIChatTextVerbosity? = nil,
        promptCacheKey: String? = nil,
        promptCacheRetention: OpenAIChatPromptCacheRetention? = nil,
        safetyIdentifier: String? = nil,
        systemMessageMode: OpenAIChatSystemMessageMode? = nil,
        forceReasoning: Bool? = nil
    ) {
        self.logitBias = logitBias
        self.logprobs = logprobs
        self.parallelToolCalls = parallelToolCalls
        self.user = user
        self.reasoningEffort = reasoningEffort
        self.maxCompletionTokens = maxCompletionTokens
        self.store = store
        self.metadata = metadata
        self.prediction = prediction
        self.serviceTier = serviceTier
        self.strictJsonSchema = strictJsonSchema
        self.textVerbosity = textVerbosity
        self.promptCacheKey = promptCacheKey
        self.promptCacheRetention = promptCacheRetention
        self.safetyIdentifier = safetyIdentifier
        self.systemMessageMode = systemMessageMode
        self.forceReasoning = forceReasoning
    }
}

public typealias OpenAILanguageModelChatOptions = OpenAIChatProviderOptions
public typealias OpenAIChatLanguageModelOptions = OpenAIChatProviderOptions


private let openAIChatProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

let openAIChatProviderOptionsSchema = FlexibleSchema<OpenAIChatProviderOptions>(
    Schema(
        jsonSchemaResolver: { openAIChatProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var result = OpenAIChatProviderOptions()
                func field(_ key: String, message: String) throws -> JSONValue? {
                    guard let value = dict[key] else { return nil }
                    guard value != .null else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: message)
                        throw TypeValidationError.wrap(value: value, cause: error)
                    }
                    return value
                }

                if let logitBiasValue = try field("logitBias", message: "logitBias must be an object") {
                    guard case .object(let entries) = logitBiasValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "logitBias must be an object")
                        return .failure(error: TypeValidationError.wrap(value: logitBiasValue, cause: error))
                    }
                    var bias: [String: Double] = [:]
                    for (key, value) in entries {
                        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let keyNumber = Double(trimmedKey), keyNumber.isFinite {
                            // ok
                        } else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "logitBias keys must be numbers")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        guard case .number(let number) = value else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "logitBias values must be numbers")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        bias[key] = number
                    }
                    result.logitBias = bias
                }

                if let logprobsValue = try field("logprobs", message: "logprobs must be boolean or number") {
                    switch logprobsValue {
                    case .bool(let flag):
                        result.logprobs = .bool(flag)
                    case .number(let number):
                        result.logprobs = .number(number)
                    default:
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "logprobs must be boolean or number")
                        return .failure(error: TypeValidationError.wrap(value: logprobsValue, cause: error))
                    }
                }

                if let parallel = try field("parallelToolCalls", message: "parallelToolCalls must be a boolean") {
                    guard case .bool(let flag) = parallel else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "parallelToolCalls must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: parallel, cause: error))
                    }
                    result.parallelToolCalls = flag
                }

                if let userValue = try field("user", message: "user must be a string") {
                    guard case .string(let string) = userValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "user must be a string")
                        return .failure(error: TypeValidationError.wrap(value: userValue, cause: error))
                    }
                    result.user = string
                }

                if let reasoningValue = try field("reasoningEffort", message: "reasoningEffort must be one of minimal, low, medium, high") {
                    guard case .string(let string) = reasoningValue,
                          let effort = OpenAIChatReasoningEffort(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "reasoningEffort must be one of minimal, low, medium, high")
                        return .failure(error: TypeValidationError.wrap(value: reasoningValue, cause: error))
                    }
                    result.reasoningEffort = effort
                }

                if let maxCompletionTokens = try field("maxCompletionTokens", message: "maxCompletionTokens must be a number") {
                    guard case .number(let number) = maxCompletionTokens else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "maxCompletionTokens must be a number")
                        return .failure(error: TypeValidationError.wrap(value: maxCompletionTokens, cause: error))
                    }
                    result.maxCompletionTokens = number
                }

                if let storeValue = try field("store", message: "store must be a boolean") {
                    guard case .bool(let flag) = storeValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "store must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: storeValue, cause: error))
                    }
                    result.store = flag
                }

                if let metadataValue = try field("metadata", message: "metadata must be an object") {
                    guard case .object(let entries) = metadataValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "metadata must be an object")
                        return .failure(error: TypeValidationError.wrap(value: metadataValue, cause: error))
                    }
                    var metadata: [String: String] = [:]
                    for (key, value) in entries {
                        if key.utf16.count > 64 {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "metadata keys must be at most 64 characters")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        guard case .string(let stringValue) = value else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "metadata values must be strings")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        if stringValue.utf16.count > 512 {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "metadata values must be at most 512 characters")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        metadata[key] = stringValue
                    }
                    result.metadata = metadata
                }

                if let predictionValue = try field("prediction", message: "prediction must be an object") {
                    guard case .object(let entries) = predictionValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "prediction must be an object")
                        return .failure(error: TypeValidationError.wrap(value: predictionValue, cause: error))
                    }
                    result.prediction = entries
                }

                if let tierValue = try field("serviceTier", message: "serviceTier must be one of auto, flex, priority, default") {
                    guard case .string(let string) = tierValue,
                          let tier = OpenAIChatServiceTier(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "serviceTier must be one of auto, flex, priority, default")
                        return .failure(error: TypeValidationError.wrap(value: tierValue, cause: error))
                    }
                    result.serviceTier = tier
                }

                if let strictValue = try field("strictJsonSchema", message: "strictJsonSchema must be a boolean") {
                    guard case .bool(let flag) = strictValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "strictJsonSchema must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: strictValue, cause: error))
                    }
                    result.strictJsonSchema = flag
                }

                if let verbosityValue = try field("textVerbosity", message: "textVerbosity must be one of low, medium, high") {
                    guard case .string(let string) = verbosityValue,
                          let verbosity = OpenAIChatTextVerbosity(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "textVerbosity must be one of low, medium, high")
                        return .failure(error: TypeValidationError.wrap(value: verbosityValue, cause: error))
                    }
                    result.textVerbosity = verbosity
                }

                if let cacheKeyValue = try field("promptCacheKey", message: "promptCacheKey must be a string") {
                    guard case .string(let string) = cacheKeyValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "promptCacheKey must be a string")
                        return .failure(error: TypeValidationError.wrap(value: cacheKeyValue, cause: error))
                    }
                    result.promptCacheKey = string
                }

                if let cacheRetentionValue = try field("promptCacheRetention", message: "promptCacheRetention must be one of in_memory, 24h") {
                    guard case .string(let string) = cacheRetentionValue,
                          let retention = OpenAIChatPromptCacheRetention(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "promptCacheRetention must be one of in_memory, 24h")
                        return .failure(error: TypeValidationError.wrap(value: cacheRetentionValue, cause: error))
                    }
                    result.promptCacheRetention = retention
                }

                if let safetyValue = try field("safetyIdentifier", message: "safetyIdentifier must be a string") {
                    guard case .string(let string) = safetyValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "safetyIdentifier must be a string")
                        return .failure(error: TypeValidationError.wrap(value: safetyValue, cause: error))
                    }
                    result.safetyIdentifier = string
                }

                if let systemModeValue = try field("systemMessageMode", message: "systemMessageMode must be a string") {
                    guard case .string(let rawMode) = systemModeValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "systemMessageMode must be a string")
                        return .failure(error: TypeValidationError.wrap(value: systemModeValue, cause: error))
                    }
                    switch rawMode {
                    case "system":
                        result.systemMessageMode = .system
                    case "developer":
                        result.systemMessageMode = .developer
                    case "remove":
                        result.systemMessageMode = .remove
                    default:
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "systemMessageMode must be one of system, developer, remove")
                        return .failure(error: TypeValidationError.wrap(value: systemModeValue, cause: error))
                    }
                }

                if let forceReasoningValue = try field("forceReasoning", message: "forceReasoning must be a boolean") {
                    guard case .bool(let flag) = forceReasoningValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "forceReasoning must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: forceReasoningValue, cause: error))
                    }
                    result.forceReasoning = flag
                }

                return .success(value: result)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
