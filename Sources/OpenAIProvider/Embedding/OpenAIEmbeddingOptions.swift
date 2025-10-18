import Foundation
import AISDKProvider
import AISDKProviderUtils

private func parseOptionalInt(_ dict: [String: JSONValue], key: String) throws -> Int? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .number(let number) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a number")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    let intValue = Int(number)
    if Double(intValue) != number {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be an integer")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return intValue
}

private func parseOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .string(let string) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return string
}

public struct OpenAIEmbeddingProviderOptions: Sendable, Equatable {
    public let dimensions: Int?
    public let user: String?

    public init(dimensions: Int? = nil, user: String? = nil) {
        self.dimensions = dimensions
        self.user = user
    }
}

private let openaiEmbeddingProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
    "properties": .object([
        "dimensions": .object([
            "type": .array([.string("number"), .string("null")])
        ]),
        "user": .object([
            "type": .array([.string("string"), .string("null")])
        ])
    ])
])

public let openaiEmbeddingProviderOptionsSchema = FlexibleSchema<OpenAIEmbeddingProviderOptions>(
    Schema(
        jsonSchemaResolver: { openaiEmbeddingProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let options = OpenAIEmbeddingProviderOptions(
                    dimensions: try parseOptionalInt(dict, key: "dimensions"),
                    user: try parseOptionalString(dict, key: "user")
                )

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
