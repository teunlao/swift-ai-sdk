import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-embedding-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public enum BedrockEmbeddingDimensions: Int, Sendable, Equatable {
    case d1024 = 1024
    case d512 = 512
    case d256 = 256
}

public struct BedrockEmbeddingProviderOptions: Sendable, Equatable {
    public var dimensions: BedrockEmbeddingDimensions?
    public var normalize: Bool?

    public init(dimensions: BedrockEmbeddingDimensions? = nil, normalize: Bool? = nil) {
        self.dimensions = dimensions
        self.normalize = normalize
    }
}

private let embeddingOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let bedrockEmbeddingProviderOptionsSchema = FlexibleSchema(
    Schema<BedrockEmbeddingProviderOptions>(
        jsonSchemaResolver: { embeddingOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let object) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "bedrock",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var dimensions: BedrockEmbeddingDimensions? = nil
                if let rawDimensions = object["dimensions"], rawDimensions != .null {
                    guard case .number(let number) = rawDimensions,
                          let parsed = BedrockEmbeddingDimensions(rawValue: Int(number)),
                          Double(parsed.rawValue) == number else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "dimensions must be one of 1024, 512, 256"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawDimensions, cause: error))
                    }
                    dimensions = parsed
                }

                var normalize: Bool? = nil
                if let rawNormalize = object["normalize"], rawNormalize != .null {
                    guard case .bool(let boolValue) = rawNormalize else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "normalize must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawNormalize, cause: error))
                    }
                    normalize = boolValue
                }

                return .success(value: BedrockEmbeddingProviderOptions(dimensions: dimensions, normalize: normalize))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
