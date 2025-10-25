import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-chat-options.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct CohereChatOptions: Sendable, Equatable {
    public struct Thinking: Sendable, Equatable {
        public enum ThinkingType: String, Sendable, Equatable {
            case enabled = "enabled"
            case disabled = "disabled"
        }

        public var type: ThinkingType?
        public var tokenBudget: Int?

        public init(type: ThinkingType? = nil, tokenBudget: Int? = nil) {
            self.type = type
            self.tokenBudget = tokenBudget
        }
    }

    public var thinking: Thinking?

    public init(thinking: Thinking? = nil) {
        self.thinking = thinking
    }
}

private let cohereChatOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let cohereChatOptionsSchema = FlexibleSchema(
    Schema<CohereChatOptions>(
        jsonSchemaResolver: { cohereChatOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "cohere",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = CohereChatOptions()

                if let thinkingValue = dict["thinking"], thinkingValue != .null {
                    guard case .object(let thinkingObject) = thinkingValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "thinking must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    var thinking = CohereChatOptions.Thinking()

                    if let typeValue = thinkingObject["type"], typeValue != .null {
                        guard case .string(let typeString) = typeValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "cohere",
                                issues: "thinking.type must be a string"
                            )
                            return .failure(error: TypeValidationError.wrap(value: typeValue, cause: error))
                        }

                        guard let resolvedType = CohereChatOptions.Thinking.ThinkingType(rawValue: typeString) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "cohere",
                                issues: "thinking.type must be 'enabled' or 'disabled'"
                            )
                            return .failure(error: TypeValidationError.wrap(value: typeValue, cause: error))
                        }

                        thinking.type = resolvedType
                    }

                    if let tokenBudgetValue = thinkingObject["tokenBudget"], tokenBudgetValue != .null {
                        guard case .number(let number) = tokenBudgetValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "cohere",
                                issues: "thinking.tokenBudget must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: tokenBudgetValue, cause: error))
                        }
                        thinking.tokenBudget = Int(number)
                    }

                    options.thinking = thinking
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
