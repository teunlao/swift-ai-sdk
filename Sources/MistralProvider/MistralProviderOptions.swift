import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-chat-options.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct MistralProviderOptions: Sendable, Equatable {
    public var safePrompt: Bool?
    public var documentImageLimit: Int?
    public var documentPageLimit: Int?
    public var structuredOutputs: Bool?
    public var strictJsonSchema: Bool?
    public var parallelToolCalls: Bool?

    public init(
        safePrompt: Bool? = nil,
        documentImageLimit: Int? = nil,
        documentPageLimit: Int? = nil,
        structuredOutputs: Bool? = nil,
        strictJsonSchema: Bool? = nil,
        parallelToolCalls: Bool? = nil
    ) {
        self.safePrompt = safePrompt
        self.documentImageLimit = documentImageLimit
        self.documentPageLimit = documentPageLimit
        self.structuredOutputs = structuredOutputs
        self.strictJsonSchema = strictJsonSchema
        self.parallelToolCalls = parallelToolCalls
    }
}

private let mistralProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let mistralProviderOptionsSchema = FlexibleSchema(
    Schema<MistralProviderOptions>(
        jsonSchemaResolver: { mistralProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "mistral",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = MistralProviderOptions()

                if let safePromptValue = dict["safePrompt"], safePromptValue != .null {
                    guard case .bool(let bool) = safePromptValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "mistral",
                            issues: "safePrompt must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: safePromptValue, cause: error))
                    }
                    options.safePrompt = bool
                }

                if let imageLimitValue = dict["documentImageLimit"], imageLimitValue != .null {
                    guard case .number(let number) = imageLimitValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "mistral",
                            issues: "documentImageLimit must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: imageLimitValue, cause: error))
                    }
                    options.documentImageLimit = Int(number)
                }

                if let pageLimitValue = dict["documentPageLimit"], pageLimitValue != .null {
                    guard case .number(let number) = pageLimitValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "mistral",
                            issues: "documentPageLimit must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: pageLimitValue, cause: error))
                    }
                    options.documentPageLimit = Int(number)
                }

                if let structuredValue = dict["structuredOutputs"], structuredValue != .null {
                    guard case .bool(let bool) = structuredValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "mistral",
                            issues: "structuredOutputs must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: structuredValue, cause: error))
                    }
                    options.structuredOutputs = bool
                }

                if let strictValue = dict["strictJsonSchema"], strictValue != .null {
                    guard case .bool(let bool) = strictValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "mistral",
                            issues: "strictJsonSchema must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: strictValue, cause: error))
                    }
                    options.strictJsonSchema = bool
                }

                if let parallelValue = dict["parallelToolCalls"], parallelValue != .null {
                    guard case .bool(let bool) = parallelValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "mistral",
                            issues: "parallelToolCalls must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: parallelValue, cause: error))
                    }
                    options.parallelToolCalls = bool
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
