import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-chat-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public enum BedrockReasoningType: String, Sendable, Equatable {
    case enabled
    case disabled
}

public struct BedrockReasoningConfig: Sendable, Equatable {
    public var type: BedrockReasoningType?
    public var budgetTokens: Int?

    public init(type: BedrockReasoningType? = nil, budgetTokens: Int? = nil) {
        self.type = type
        self.budgetTokens = budgetTokens
    }
}

public struct BedrockProviderOptions: Sendable, Equatable {
    public var additionalModelRequestFields: [String: JSONValue]?
    public var reasoningConfig: BedrockReasoningConfig?
    public var guardrailConfig: JSONValue?

    public init(
        additionalModelRequestFields: [String: JSONValue]? = nil,
        reasoningConfig: BedrockReasoningConfig? = nil,
        guardrailConfig: JSONValue? = nil
    ) {
        self.additionalModelRequestFields = additionalModelRequestFields
        self.reasoningConfig = reasoningConfig
        self.guardrailConfig = guardrailConfig
    }
}

public struct BedrockFilePartProviderOptions: Sendable, Equatable {
    public struct Citations: Sendable, Equatable {
        public var enabled: Bool

        public init(enabled: Bool) {
            self.enabled = enabled
        }
    }

    public var citations: Citations?

    public init(citations: Citations? = nil) {
        self.citations = citations
    }
}

private let providerOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

private let filePartOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let bedrockProviderOptionsSchema = FlexibleSchema(
    Schema<BedrockProviderOptions>(
        jsonSchemaResolver: { providerOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "bedrock",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var additionalFields: [String: JSONValue]? = nil
                if let rawAdditional = dict["additionalModelRequestFields"], rawAdditional != .null {
                    guard case .object(let fields) = rawAdditional else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "additionalModelRequestFields must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawAdditional, cause: error))
                    }
                    additionalFields = fields
                }

                var reasoningConfig: BedrockReasoningConfig? = nil
                if let rawReasoning = dict["reasoningConfig"], rawReasoning != .null {
                    guard case .object(let reasoningDict) = rawReasoning else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "reasoningConfig must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawReasoning, cause: error))
                    }

                    var parsed = BedrockReasoningConfig()
                    if let rawType = reasoningDict["type"], rawType != .null {
                        guard case .string(let typeString) = rawType,
                              let type = BedrockReasoningType(rawValue: typeString) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "bedrock",
                                issues: "reasoningConfig.type must be 'enabled' or 'disabled'"
                            )
                            return .failure(error: TypeValidationError.wrap(value: rawType, cause: error))
                        }
                        parsed.type = type
                    }

                    if let rawBudget = reasoningDict["budgetTokens"], rawBudget != .null {
                        guard case .number(let number) = rawBudget else {
                            let error = SchemaValidationIssuesError(
                                vendor: "bedrock",
                                issues: "reasoningConfig.budgetTokens must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: rawBudget, cause: error))
                        }
                        let intValue = Int(number)
                        if Double(intValue) != number {
                            let error = SchemaValidationIssuesError(
                                vendor: "bedrock",
                                issues: "reasoningConfig.budgetTokens must be an integer"
                            )
                            return .failure(error: TypeValidationError.wrap(value: rawBudget, cause: error))
                        }
                        parsed.budgetTokens = intValue
                    }

                    reasoningConfig = parsed
                }

                var guardrailConfig: JSONValue? = nil
                if let rawGuardrail = dict["guardrailConfig"], rawGuardrail != .null {
                    guard case .object = rawGuardrail else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "guardrailConfig must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawGuardrail, cause: error))
                    }
                    guardrailConfig = rawGuardrail
                }

                return .success(
                    value: BedrockProviderOptions(
                        additionalModelRequestFields: additionalFields,
                        reasoningConfig: reasoningConfig,
                        guardrailConfig: guardrailConfig
                    )
                )
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

public let bedrockFilePartProviderOptionsSchema = FlexibleSchema(
    Schema<BedrockFilePartProviderOptions>(
        jsonSchemaResolver: { filePartOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "bedrock",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var citations: BedrockFilePartProviderOptions.Citations? = nil
                if let rawCitations = dict["citations"], rawCitations != .null {
                    guard case .object(let citationsDict) = rawCitations else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "citations must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawCitations, cause: error))
                    }

                    guard let enabledValue = citationsDict["enabled"], enabledValue != .null else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "citations.enabled must be provided"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawCitations, cause: error))
                    }

                    guard case .bool(let enabled) = enabledValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "citations.enabled must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: enabledValue, cause: error))
                    }

                    citations = .init(enabled: enabled)
                }

                return .success(value: BedrockFilePartProviderOptions(citations: citations))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
