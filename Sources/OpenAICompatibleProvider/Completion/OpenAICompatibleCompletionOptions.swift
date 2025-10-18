import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleCompletionProviderOptions: Sendable, Equatable {
    public var echo: Bool?
    public var logitBias: [String: Double]?
    public var suffix: String?
    public var user: String?

    public init(echo: Bool? = nil, logitBias: [String: Double]? = nil, suffix: String? = nil, user: String? = nil) {
        self.echo = echo
        self.logitBias = logitBias
        self.suffix = suffix
        self.user = user
    }
}

private let openAICompatibleCompletionOptionsSchemaJSON: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let openAICompatibleCompletionProviderOptionsSchema = FlexibleSchema(
    Schema<OpenAICompatibleCompletionProviderOptions>(
        jsonSchemaResolver: { openAICompatibleCompletionOptionsSchemaJSON },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAICompatibleCompletionProviderOptions()

                if let echoValue = dict["echo"], echoValue != .null {
                    guard case .bool(let echo) = echoValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "echo must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: echoValue, cause: error))
                    }
                    options.echo = echo
                }

                if let logitBiasValue = dict["logitBias"], logitBiasValue != .null {
                    guard case .object(let rawBias) = logitBiasValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "logitBias must be an object")
                        return .failure(error: TypeValidationError.wrap(value: logitBiasValue, cause: error))
                    }
                    var bias: [String: Double] = [:]
                    for (key, rawValue) in rawBias {
                        guard case .number(let number) = rawValue else {
                            let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "logitBias values must be numbers")
                            return .failure(error: TypeValidationError.wrap(value: rawValue, cause: error))
                        }
                        bias[key] = number
                    }
                    options.logitBias = bias
                }

                if let suffixValue = dict["suffix"], suffixValue != .null {
                    guard case .string(let suffix) = suffixValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "suffix must be a string")
                        return .failure(error: TypeValidationError.wrap(value: suffixValue, cause: error))
                    }
                    options.suffix = suffix
                }

                if let userValue = dict["user"], userValue != .null {
                    guard case .string(let user) = userValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "user must be a string")
                        return .failure(error: TypeValidationError.wrap(value: userValue, cause: error))
                    }
                    options.user = user
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
