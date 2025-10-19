import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GroqReasoningFormat: String, Sendable, Equatable {
    case parsed
    case raw
    case hidden
}

public enum GroqServiceTier: String, Sendable, Equatable {
    case onDemand = "on_demand"
    case flex = "flex"
    case auto = "auto"
}

public struct GroqProviderOptions: Sendable, Equatable {
    public var reasoningFormat: GroqReasoningFormat?
    public var reasoningEffort: String?
    public var parallelToolCalls: Bool?
    public var user: String?
    public var structuredOutputs: Bool?
    public var serviceTier: GroqServiceTier?

    public init(
        reasoningFormat: GroqReasoningFormat? = nil,
        reasoningEffort: String? = nil,
        parallelToolCalls: Bool? = nil,
        user: String? = nil,
        structuredOutputs: Bool? = nil,
        serviceTier: GroqServiceTier? = nil
    ) {
        self.reasoningFormat = reasoningFormat
        self.reasoningEffort = reasoningEffort
        self.parallelToolCalls = parallelToolCalls
        self.user = user
        self.structuredOutputs = structuredOutputs
        self.serviceTier = serviceTier
    }
}

private let groqProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let groqProviderOptionsSchema = FlexibleSchema(
    Schema<GroqProviderOptions>(
        jsonSchemaResolver: { groqProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "groq",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = GroqProviderOptions()

                if let reasoningFormatValue = dict["reasoningFormat"], reasoningFormatValue != .null {
                    guard case .string(let raw) = reasoningFormatValue,
                          let parsed = GroqReasoningFormat(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "groq",
                            issues: "reasoningFormat must be 'parsed', 'raw', or 'hidden'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: reasoningFormatValue, cause: error))
                    }
                    options.reasoningFormat = parsed
                }

                if let reasoningEffortValue = dict["reasoningEffort"], reasoningEffortValue != .null {
                    guard case .string(let string) = reasoningEffortValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "groq",
                            issues: "reasoningEffort must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: reasoningEffortValue, cause: error))
                    }
                    options.reasoningEffort = string
                }

                if let parallelValue = dict["parallelToolCalls"], parallelValue != .null {
                    guard case .bool(let bool) = parallelValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "groq",
                            issues: "parallelToolCalls must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: parallelValue, cause: error))
                    }
                    options.parallelToolCalls = bool
                }

                if let userValue = dict["user"], userValue != .null {
                    guard case .string(let string) = userValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "groq",
                            issues: "user must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: userValue, cause: error))
                    }
                    options.user = string
                }

                if let structuredValue = dict["structuredOutputs"], structuredValue != .null {
                    guard case .bool(let bool) = structuredValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "groq",
                            issues: "structuredOutputs must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: structuredValue, cause: error))
                    }
                    options.structuredOutputs = bool
                }

                if let serviceTierValue = dict["serviceTier"], serviceTierValue != .null {
                    guard case .string(let raw) = serviceTierValue,
                          let tier = GroqServiceTier(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "groq",
                            issues: "serviceTier must be 'on_demand', 'flex', or 'auto'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: serviceTierValue, cause: error))
                    }
                    options.serviceTier = tier
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
