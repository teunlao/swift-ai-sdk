import Foundation
import AISDKProvider
import AISDKProviderUtils

/// xAI responses model identifiers.
/// Mirrors `packages/xai/src/responses/xai-responses-options.ts`.
public typealias XaiResponsesModelId = XAIResponsesModelId

public enum XAIResponsesReasoningEffort: String, Sendable, Equatable {
    case low
    case medium
    case high
}

public struct XAILanguageModelResponsesOptions: Sendable, Equatable {
    public var reasoningEffort: XAIResponsesReasoningEffort?
    public var store: Bool?
    public var previousResponseId: String?
    public var include: [String]?

    public init(
        reasoningEffort: XAIResponsesReasoningEffort? = nil,
        store: Bool? = nil,
        previousResponseId: String? = nil,
        include: [String]? = nil
    ) {
        self.reasoningEffort = reasoningEffort
        self.store = store
        self.previousResponseId = previousResponseId
        self.include = include
    }
}

private let xaiResponsesProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let xaiLanguageModelResponsesOptionsSchema = FlexibleSchema(
    Schema<XAILanguageModelResponsesOptions>(
        jsonSchemaResolver: { xaiResponsesProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var reasoningEffort: XAIResponsesReasoningEffort? = nil
                if let raw = dict["reasoningEffort"], raw != .null {
                    guard case .string(let value) = raw,
                          let parsed = XAIResponsesReasoningEffort(rawValue: value) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "reasoningEffort must be 'low', 'medium', or 'high'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    reasoningEffort = parsed
                }

                var store: Bool? = nil
                if let raw = dict["store"], raw != .null {
                    guard case .bool(let value) = raw else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "store must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    store = value
                }

                var previousResponseId: String? = nil
                if let raw = dict["previousResponseId"], raw != .null {
                    guard case .string(let value) = raw else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "previousResponseId must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    previousResponseId = value
                }

                var include: [String]? = nil
                if let raw = dict["include"], raw != .null {
                    guard case .array(let values) = raw else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "include must be an array of strings or null"
                        )
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }

                    var parsed: [String] = []
                    for item in values {
                        guard case .string(let value) = item else {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "include must be an array of strings"
                            )
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        if value != "file_search_call.results" {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "include can only contain 'file_search_call.results'"
                            )
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        parsed.append(value)
                    }
                    include = parsed
                }

                return .success(value: XAILanguageModelResponsesOptions(
                    reasoningEffort: reasoningEffort,
                    store: store,
                    previousResponseId: previousResponseId,
                    include: include
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

