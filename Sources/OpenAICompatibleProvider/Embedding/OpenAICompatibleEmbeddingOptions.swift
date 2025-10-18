import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleEmbeddingProviderOptions: Sendable, Equatable {
    public var dimensions: Int?
    public var user: String?

    public init(dimensions: Int? = nil, user: String? = nil) {
        self.dimensions = dimensions
        self.user = user
    }
}

private let openAICompatibleEmbeddingOptionsSchemaJSON: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let openAICompatibleEmbeddingProviderOptionsSchema = FlexibleSchema(
    Schema<OpenAICompatibleEmbeddingProviderOptions>(
        jsonSchemaResolver: { openAICompatibleEmbeddingOptionsSchemaJSON },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAICompatibleEmbeddingProviderOptions()

                if let dimensionsValue = dict["dimensions"], dimensionsValue != .null {
                    guard case .number(let number) = dimensionsValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai-compatible", issues: "dimensions must be a number")
                        return .failure(error: TypeValidationError.wrap(value: dimensionsValue, cause: error))
                    }
                    options.dimensions = Int(number)
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
