import Foundation
import AISDKProvider
import AISDKProviderUtils

private func parseOptionalNumber(_ dict: [String: JSONValue], key: String, allowNull: Bool = false) throws -> Double? {
    guard let value = dict[key] else { return nil }
    if value == .null {
        if allowNull {
            return nil
        }
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a number")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    guard case .number(let number) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a number")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return number
}

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

public struct OpenAIEmbeddingProviderOptions: Sendable, Equatable {
    public let dimensions: Double?
    public let user: String?

    public init(dimensions: Double? = nil, user: String? = nil) {
        self.dimensions = dimensions
        self.user = user
    }
}

private let openaiEmbeddingProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
    "properties": .object([
        "dimensions": .object([
            "type": .string("number")
        ]),
        "user": .object([
            "type": .string("string")
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
                    dimensions: try parseOptionalNumber(dict, key: "dimensions", allowNull: false),
                    user: try parseOptionalString(dict, key: "user", allowNull: false)
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
