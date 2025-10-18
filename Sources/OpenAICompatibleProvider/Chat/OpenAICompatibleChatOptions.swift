import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleChatProviderOptions: Sendable, Equatable {
    public var user: String?
    public var reasoningEffort: String?
    public var textVerbosity: String?

    public init(user: String? = nil, reasoningEffort: String? = nil, textVerbosity: String? = nil) {
        self.user = user
        self.reasoningEffort = reasoningEffort
        self.textVerbosity = textVerbosity
    }
}

private let openAICompatibleProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let openAICompatibleProviderOptionsSchema = FlexibleSchema(
    Schema<OpenAICompatibleChatProviderOptions>(
        jsonSchemaResolver: { openAICompatibleProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAICompatibleChatProviderOptions()

                if let userValue = dict["user"], userValue != .null {
                    guard case .string(let user) = userValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "user must be a string")
                        return .failure(error: TypeValidationError.wrap(value: userValue, cause: error))
                    }
                    options.user = user
                }

                if let reasoning = dict["reasoningEffort"], reasoning != .null {
                    guard case .string(let effort) = reasoning else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "reasoningEffort must be a string")
                        return .failure(error: TypeValidationError.wrap(value: reasoning, cause: error))
                    }
                    options.reasoningEffort = effort
                }

                if let verbosity = dict["textVerbosity"], verbosity != .null {
                    guard case .string(let text) = verbosity else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "textVerbosity must be a string")
                        return .failure(error: TypeValidationError.wrap(value: verbosity, cause: error))
                    }
                    options.textVerbosity = text
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
