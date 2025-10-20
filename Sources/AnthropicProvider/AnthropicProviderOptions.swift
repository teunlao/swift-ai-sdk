import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Known Anthropic Claude model identifiers for autocomplete.
/// See: https://docs.claude.com/en/docs/about-claude/models/overview
///
/// Port of `@ai-sdk/anthropic/src/anthropic-messages-options.ts`.
public let anthropicMessagesModelIds: [AnthropicMessagesModelId] = [
    "claude-sonnet-4-5",
    "claude-sonnet-4-5-20250929",
    "claude-opus-4-1",
    "claude-opus-4-0",
    "claude-sonnet-4-0",
    "claude-opus-4-1-20250805",
    "claude-opus-4-20250514",
    "claude-sonnet-4-20250514",
    "claude-3-7-sonnet-latest",
    "claude-3-7-sonnet-20250219",
    "claude-3-5-haiku-latest",
    "claude-3-5-haiku-20241022",
    "claude-3-haiku-20240307"
].map(AnthropicMessagesModelId.init(rawValue:))

public struct AnthropicThinkingOptions: Sendable, Equatable {
    public enum Mode: String, Sendable, Equatable {
        case enabled
        case disabled
    }

    public var type: Mode
    public var budgetTokens: Int?

    public init(type: Mode, budgetTokens: Int? = nil) {
        self.type = type
        self.budgetTokens = budgetTokens
    }
}

public struct AnthropicCacheControl: Sendable, Equatable {
    public enum TTL: String, Sendable, Equatable {
        case fiveMinutes = "5m"
        case oneHour = "1h"
    }

    public var type: String
    public var ttl: TTL?

    public init(type: String = "ephemeral", ttl: TTL? = nil) {
        self.type = type
        self.ttl = ttl
    }
}

public struct AnthropicProviderOptions: Sendable, Equatable {
    public var sendReasoning: Bool?
    public var thinking: AnthropicThinkingOptions?
    public var disableParallelToolUse: Bool?
    public var cacheControl: AnthropicCacheControl?

    public init(
        sendReasoning: Bool? = nil,
        thinking: AnthropicThinkingOptions? = nil,
        disableParallelToolUse: Bool? = nil,
        cacheControl: AnthropicCacheControl? = nil
    ) {
        self.sendReasoning = sendReasoning
        self.thinking = thinking
        self.disableParallelToolUse = disableParallelToolUse
        self.cacheControl = cacheControl
    }
}

public struct AnthropicFilePartProviderOptions: Sendable, Equatable {
    public struct Citations: Sendable, Equatable {
        public var enabled: Bool

        public init(enabled: Bool) {
            self.enabled = enabled
        }
    }

    public var citations: Citations?
    public var title: String?
    public var context: String?

    public init(citations: Citations? = nil, title: String? = nil, context: String? = nil) {
        self.citations = citations
        self.title = title
        self.context = context
    }
}

private func parseOptionalBool(_ dict: [String: JSONValue], key: String) throws -> Bool? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .bool(let bool) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "\(key) must be a boolean"))
    }
    return bool
}

private func parseOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .string(let string) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "\(key) must be a string"))
    }
    return string
}

private let anthropicProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let anthropicProviderOptionsSchema = FlexibleSchema(
    Schema<AnthropicProviderOptions>(
        jsonSchemaResolver: { anthropicProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = AnthropicProviderOptions()
                options.sendReasoning = try parseOptionalBool(dict, key: "sendReasoning")

                if let thinkingValue = dict["thinking"], thinkingValue != .null {
                    guard case .object(let thinkingDict) = thinkingValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking must be an object")
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    guard let typeValue = thinkingDict["type"], case .string(let typeRaw) = typeValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.type must be 'enabled' or 'disabled'")
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    guard let mode = AnthropicThinkingOptions.Mode(rawValue: typeRaw) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.type must be 'enabled' or 'disabled'")
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    var budget: Int?
                    if let budgetValue = thinkingDict["budgetTokens"], budgetValue != .null {
                        guard case .number(let number) = budgetValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.budgetTokens must be a number")
                            return .failure(error: TypeValidationError.wrap(value: budgetValue, cause: error))
                        }
                        let intValue = Int(number)
                        if Double(intValue) != number {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.budgetTokens must be an integer")
                            return .failure(error: TypeValidationError.wrap(value: budgetValue, cause: error))
                        }
                        budget = intValue
                    }

                    options.thinking = AnthropicThinkingOptions(type: mode, budgetTokens: budget)
                }

                options.disableParallelToolUse = try parseOptionalBool(dict, key: "disableParallelToolUse")

                if let cacheValue = dict["cacheControl"], cacheValue != .null {
                    guard case .object(let cacheDict) = cacheValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "cacheControl must be an object")
                        return .failure(error: TypeValidationError.wrap(value: cacheValue, cause: error))
                    }

                    guard let typeValue = cacheDict["type"], case .string(let typeString) = typeValue, typeString == "ephemeral" else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "cacheControl.type must be 'ephemeral'")
                        return .failure(error: TypeValidationError.wrap(value: cacheValue, cause: error))
                    }

                    var ttl: AnthropicCacheControl.TTL?
                    if let ttlValue = cacheDict["ttl"], ttlValue != .null {
                        guard case .string(let ttlRaw) = ttlValue, let parsed = AnthropicCacheControl.TTL(rawValue: ttlRaw) else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "cacheControl.ttl must be '5m' or '1h'")
                            return .failure(error: TypeValidationError.wrap(value: ttlValue, cause: error))
                        }
                        ttl = parsed
                    }

                    options.cacheControl = AnthropicCacheControl(type: "ephemeral", ttl: ttl)
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private let anthropicFilePartOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let anthropicFilePartProviderOptionsSchema = FlexibleSchema(
    Schema<AnthropicFilePartProviderOptions>(
        jsonSchemaResolver: { anthropicFilePartOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "file part options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = AnthropicFilePartProviderOptions()

                if let citationsValue = dict["citations"], citationsValue != .null {
                    guard case .object(let citationsDict) = citationsValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "citations must be an object")
                        return .failure(error: TypeValidationError.wrap(value: citationsValue, cause: error))
                    }

                    guard let enabledValue = citationsDict["enabled"], case .bool(let enabled) = enabledValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "citations.enabled must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: citationsValue, cause: error))
                    }

                    options.citations = .init(enabled: enabled)
                }

                options.title = try parseOptionalString(dict, key: "title")
                options.context = try parseOptionalString(dict, key: "context")

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
