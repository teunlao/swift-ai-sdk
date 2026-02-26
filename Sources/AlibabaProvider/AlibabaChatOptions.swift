import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/alibaba-chat-options.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct AlibabaChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension AlibabaChatModelId {
    // Commercial edition - hybrid-thinking mode (disabled by default)
    static let qwen3Max: AlibabaChatModelId = "qwen3-max"
    static let qwen3MaxPreview: AlibabaChatModelId = "qwen3-max-preview"
    static let qwenPlus: AlibabaChatModelId = "qwen-plus"
    static let qwenPlusLatest: AlibabaChatModelId = "qwen-plus-latest"
    static let qwenFlash: AlibabaChatModelId = "qwen-flash"
    static let qwenTurbo: AlibabaChatModelId = "qwen-turbo"
    static let qwenTurboLatest: AlibabaChatModelId = "qwen-turbo-latest"

    // Open-source edition - hybrid-thinking mode (enabled by default)
    static let qwen3235bA22b: AlibabaChatModelId = "qwen3-235b-a22b"
    static let qwen332b: AlibabaChatModelId = "qwen3-32b"
    static let qwen330bA3b: AlibabaChatModelId = "qwen3-30b-a3b"
    static let qwen314b: AlibabaChatModelId = "qwen3-14b"

    // Thinking-only mode
    static let qwen3Next80bA3bThinking: AlibabaChatModelId = "qwen3-next-80b-a3b-thinking"
    static let qwen3235bA22bThinking2507: AlibabaChatModelId = "qwen3-235b-a22b-thinking-2507"
    static let qwen330bA3bThinking2507: AlibabaChatModelId = "qwen3-30b-a3b-thinking-2507"
    static let qwqPlus: AlibabaChatModelId = "qwq-plus"
    static let qwqPlusLatest: AlibabaChatModelId = "qwq-plus-latest"
    static let qwq32b: AlibabaChatModelId = "qwq-32b"

    // Code models
    static let qwenCoder: AlibabaChatModelId = "qwen-coder"
    static let qwen3CoderPlus: AlibabaChatModelId = "qwen3-coder-plus"
    static let qwen3CoderFlash: AlibabaChatModelId = "qwen3-coder-flash"
}

public struct AlibabaLanguageModelOptions: Sendable, Equatable {
    /// Enable thinking/reasoning mode for supported models.
    public var enableThinking: Bool?

    /// Maximum number of reasoning tokens to generate.
    public var thinkingBudget: Double?

    /// Whether to enable parallel function calling during tool use.
    public var parallelToolCalls: Bool?

    public init(
        enableThinking: Bool? = nil,
        thinkingBudget: Double? = nil,
        parallelToolCalls: Bool? = nil
    ) {
        self.enableThinking = enableThinking
        self.thinkingBudget = thinkingBudget
        self.parallelToolCalls = parallelToolCalls
    }
}

private let alibabaLanguageModelOptionsSchema = FlexibleSchema(
    Schema<AlibabaLanguageModelOptions>(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true),
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func boolOptional(_ key: String) -> Result<Bool?, TypeValidationError> {
                    guard let raw = dict[key] else { return .success(nil) }
                    if raw == .null {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    guard case .bool(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func positiveNumberOptional(_ key: String) -> Result<Double?, TypeValidationError> {
                    guard let raw = dict[key] else { return .success(nil) }
                    if raw == .null {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    guard case .number(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    guard value > 0 else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                let enableThinking = try boolOptional("enableThinking").get()
                let thinkingBudget = try positiveNumberOptional("thinkingBudget").get()
                let parallelToolCalls = try boolOptional("parallelToolCalls").get()

                return .success(value: AlibabaLanguageModelOptions(
                    enableThinking: enableThinking,
                    thinkingBudget: thinkingBudget,
                    parallelToolCalls: parallelToolCalls
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

// Exposed internally for request mapping.
let alibabaLanguageModelOptionsFlexibleSchema = alibabaLanguageModelOptionsSchema
