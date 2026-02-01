import Foundation
import AISDKProvider
import AISDKProviderUtils

enum OpenAIChatLogprobsOption: Sendable, Equatable {
    case bool(Bool)
    case number(Int)

    var jsonValue: JSONValue {
        switch self {
        case .bool(let flag):
            return .bool(flag)
        case .number(let value):
            return .number(Double(value))
        }
    }
}

enum OpenAIChatReasoningEffort: String, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

enum OpenAIChatServiceTier: String, Sendable {
    case auto
    case flex
    case priority
    case `default`
}

enum OpenAIChatTextVerbosity: String, Sendable {
    case low
    case medium
    case high
}

enum OpenAIChatSystemMessageMode: Sendable, Equatable {
    case system
    case developer
    case remove
}

enum OpenAIChatPromptCacheRetention: String, Sendable {
    case inMemory = "in_memory"
    case twentyFourHours = "24h"
}

struct OpenAIChatProviderOptions: Sendable, Equatable {
    var logitBias: [String: Double]?
    var logprobs: OpenAIChatLogprobsOption?
    var parallelToolCalls: Bool?
    var user: String?
    var reasoningEffort: OpenAIChatReasoningEffort?
    var maxCompletionTokens: Int?
    var store: Bool?
    var metadata: [String: String]?
    var prediction: [String: JSONValue]?
    var serviceTier: OpenAIChatServiceTier?
    var strictJsonSchema: Bool?
    var textVerbosity: OpenAIChatTextVerbosity?
    var promptCacheKey: String?
    var promptCacheRetention: OpenAIChatPromptCacheRetention?
    var safetyIdentifier: String?
    var systemMessageMode: OpenAIChatSystemMessageMode?
    var forceReasoning: Bool?
}



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

                if let logitBiasValue = dict["logitBias"], logitBiasValue != .null {
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

                if let logprobsValue = dict["logprobs"], logprobsValue != .null {
                    switch logprobsValue {
                    case .bool(let flag):
                        result.logprobs = .bool(flag)
                    case .number(let number):
                        let intValue = Int(number)
                        if Double(intValue) != number {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "logprobs must be an integer when numeric")
                            return .failure(error: TypeValidationError.wrap(value: logprobsValue, cause: error))
                        }
                        result.logprobs = .number(intValue)
                    default:
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "logprobs must be boolean or number")
                        return .failure(error: TypeValidationError.wrap(value: logprobsValue, cause: error))
                    }
                }

                if let parallel = dict["parallelToolCalls"], parallel != .null {
                    guard case .bool(let flag) = parallel else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "parallelToolCalls must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: parallel, cause: error))
                    }
                    result.parallelToolCalls = flag
                }

                if let userValue = dict["user"], userValue != .null {
                    guard case .string(let string) = userValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "user must be a string")
                        return .failure(error: TypeValidationError.wrap(value: userValue, cause: error))
                    }
                    result.user = string
                }

                if let reasoningValue = dict["reasoningEffort"], reasoningValue != .null {
                    guard case .string(let string) = reasoningValue,
                          let effort = OpenAIChatReasoningEffort(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "reasoningEffort must be one of minimal, low, medium, high")
                        return .failure(error: TypeValidationError.wrap(value: reasoningValue, cause: error))
                    }
                    result.reasoningEffort = effort
                }

                if let maxCompletionTokens = dict["maxCompletionTokens"], maxCompletionTokens != .null {
                    guard case .number(let number) = maxCompletionTokens else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "maxCompletionTokens must be a number")
                        return .failure(error: TypeValidationError.wrap(value: maxCompletionTokens, cause: error))
                    }
                    let intValue = Int(number)
                    if Double(intValue) != number {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "maxCompletionTokens must be an integer")
                        return .failure(error: TypeValidationError.wrap(value: maxCompletionTokens, cause: error))
                    }
                    result.maxCompletionTokens = intValue
                }

                if let storeValue = dict["store"], storeValue != .null {
                    guard case .bool(let flag) = storeValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "store must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: storeValue, cause: error))
                    }
                    result.store = flag
                }

                if let metadataValue = dict["metadata"], metadataValue != .null {
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

                if let predictionValue = dict["prediction"], predictionValue != .null {
                    guard case .object(let entries) = predictionValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "prediction must be an object")
                        return .failure(error: TypeValidationError.wrap(value: predictionValue, cause: error))
                    }
                    result.prediction = entries
                }

                if let tierValue = dict["serviceTier"], tierValue != .null {
                    guard case .string(let string) = tierValue,
                          let tier = OpenAIChatServiceTier(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "serviceTier must be one of auto, flex, priority, default")
                        return .failure(error: TypeValidationError.wrap(value: tierValue, cause: error))
                    }
                    result.serviceTier = tier
                }

                if let strictValue = dict["strictJsonSchema"], strictValue != .null {
                    guard case .bool(let flag) = strictValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "strictJsonSchema must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: strictValue, cause: error))
                    }
                    result.strictJsonSchema = flag
                }

                if let verbosityValue = dict["textVerbosity"], verbosityValue != .null {
                    guard case .string(let string) = verbosityValue,
                          let verbosity = OpenAIChatTextVerbosity(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "textVerbosity must be one of low, medium, high")
                        return .failure(error: TypeValidationError.wrap(value: verbosityValue, cause: error))
                    }
                    result.textVerbosity = verbosity
                }

                if let cacheKeyValue = dict["promptCacheKey"], cacheKeyValue != .null {
                    guard case .string(let string) = cacheKeyValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "promptCacheKey must be a string")
                        return .failure(error: TypeValidationError.wrap(value: cacheKeyValue, cause: error))
                    }
                    result.promptCacheKey = string
                }

                if let cacheRetentionValue = dict["promptCacheRetention"], cacheRetentionValue != .null {
                    guard case .string(let string) = cacheRetentionValue,
                          let retention = OpenAIChatPromptCacheRetention(rawValue: string) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "promptCacheRetention must be one of in_memory, 24h")
                        return .failure(error: TypeValidationError.wrap(value: cacheRetentionValue, cause: error))
                    }
                    result.promptCacheRetention = retention
                }

                if let safetyValue = dict["safetyIdentifier"], safetyValue != .null {
                    guard case .string(let string) = safetyValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "safetyIdentifier must be a string")
                        return .failure(error: TypeValidationError.wrap(value: safetyValue, cause: error))
                    }
                    result.safetyIdentifier = string
                }

                if let systemModeValue = dict["systemMessageMode"], systemModeValue != .null {
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

                if let forceReasoningValue = dict["forceReasoning"], forceReasoningValue != .null {
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
