import Foundation
import AISDKProvider
import AISDKProviderUtils

enum OpenAICompletionLogprobsOption: Sendable, Equatable {
    case bool(Bool)
    case number(Int)

    var jsonValue: JSONValue {
        switch self {
        case .bool(let value):
            return .bool(value)
        case .number(let value):
            return .number(Double(value))
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
        "echo": .object(["type": .array([.string("boolean"), .string("null")])]),
        "logitBias": .object(["type": .array([.string("object"), .string("null")])]),
        "suffix": .object(["type": .array([.string("string"), .string("null")])]),
        "user": .object(["type": .array([.string("string"), .string("null")])]),
        "logprobs": .object(["type": .array([.string("boolean"), .string("number"), .string("null")])])
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

                if let echoValue = dict["echo"], echoValue != .null {
                    guard case .bool(let boolValue) = echoValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "echo must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: echoValue, cause: error))
                    }
                    options.echo = boolValue
                }

                if let logitBiasValue = dict["logitBias"], logitBiasValue != .null {
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

                options.suffix = try parseOptionalString(dict, key: "suffix")
                options.user = try parseOptionalString(dict, key: "user")

                if let logprobsValue = dict["logprobs"], logprobsValue != .null {
                    switch logprobsValue {
                    case .bool(let flag):
                        options.logprobs = .bool(flag)
                    case .number(let number):
                        let intValue = Int(number)
                        if Double(intValue) != number {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "logprobs must be an integer when numeric")
                            return .failure(error: TypeValidationError.wrap(value: logprobsValue, cause: error))
                        }
                        options.logprobs = .number(intValue)
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


private func parseOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .string(let string) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return string
}
