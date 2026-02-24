import Foundation
import AISDKProvider
import AISDKProviderUtils

enum OpenAICompletionLogprobsOption: Sendable, Equatable {
    case bool(Bool)
    case number(Double)

    var jsonValue: JSONValue {
        switch self {
        case .bool(let value):
            return .bool(value)
        case .number(let value):
            return .number(value)
        }
    }
}

struct OpenAICompletionProviderOptions: Sendable, Equatable {
    var echo: Bool?
    var logitBias: [String: Double]?
    var suffix: String?
    var user: String?
    var logprobs: OpenAICompletionLogprobsOption?

    init(echo: Bool? = nil, logitBias: [String: Double]? = nil, suffix: String? = nil, user: String? = nil, logprobs: OpenAICompletionLogprobsOption? = nil) {
        self.echo = echo
        self.logitBias = logitBias
        self.suffix = suffix
        self.user = user
        self.logprobs = logprobs
    }

    init() {
        self.init(echo: nil, logitBias: nil, suffix: nil, user: nil, logprobs: nil)
    }
}

private let openAICompletionProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
    "properties": .object([
        "echo": .object(["type": .string("boolean")]),
        "logitBias": .object(["type": .string("object")]),
        "suffix": .object(["type": .string("string")]),
        "user": .object(["type": .string("string")]),
        "logprobs": .object(["type": .array([.string("boolean"), .string("number")])])
    ])
])

let openAICompletionProviderOptionsSchema = FlexibleSchema<OpenAICompletionProviderOptions>(
    Schema(
        jsonSchemaResolver: { openAICompletionProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAICompletionProviderOptions()
                func field(_ key: String, message: String) throws -> JSONValue? {
                    guard let value = dict[key] else { return nil }
                    guard value != .null else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: message)
                        throw TypeValidationError.wrap(value: value, cause: error)
                    }
                    return value
                }

                if let echoValue = try field("echo", message: "echo must be a boolean") {
                    guard case .bool(let boolValue) = echoValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "echo must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: echoValue, cause: error))
                    }
                    options.echo = boolValue
                }

                if let logitBiasValue = try field("logitBias", message: "logitBias must be an object") {
                    guard case .object(let biasObject) = logitBiasValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "logitBias must be an object")
                        return .failure(error: TypeValidationError.wrap(value: logitBiasValue, cause: error))
                    }
                    var bias: [String: Double] = [:]
                    for (key, entry) in biasObject {
                        guard case .number(let number) = entry else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "logitBias values must be numbers")
                            return .failure(error: TypeValidationError.wrap(value: entry, cause: error))
                        }
                        bias[key] = number
                    }
                    options.logitBias = bias
                }

                options.suffix = try parseOptionalString(dict, key: "suffix", allowNull: false)
                options.user = try parseOptionalString(dict, key: "user", allowNull: false)

                if let logprobsValue = try field("logprobs", message: "logprobs must be boolean or number") {
                    switch logprobsValue {
                    case .bool(let flag):
                        options.logprobs = .bool(flag)
                    case .number(let number):
                        options.logprobs = .number(number)
                    default:
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "logprobs must be boolean or number")
                        return .failure(error: TypeValidationError.wrap(value: logprobsValue, cause: error))
                    }
                }

                return .success(value: options)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)


private func parseOptionalString(_ dict: [String: JSONValue], key: String, allowNull: Bool = false) throws -> String? {
    guard let value = dict[key] else { return nil }
    if value == .null {
        if allowNull {
            return nil
        }
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    guard case .string(let string) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return string
}
