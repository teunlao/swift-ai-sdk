import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-embedding-options.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

public enum BedrockEmbeddingDimensions: Int, Sendable, Equatable {
    case d1024 = 1024
    case d512 = 512
    case d256 = 256
}

public enum BedrockNovaEmbeddingDimension: Int, Sendable, Equatable {
    case d256 = 256
    case d384 = 384
    case d1024 = 1024
    case d3072 = 3072
}

public enum BedrockEmbeddingPurpose: String, Sendable, Equatable {
    case genericIndex = "GENERIC_INDEX"
    case textRetrieval = "TEXT_RETRIEVAL"
    case imageRetrieval = "IMAGE_RETRIEVAL"
    case videoRetrieval = "VIDEO_RETRIEVAL"
    case documentRetrieval = "DOCUMENT_RETRIEVAL"
    case audioRetrieval = "AUDIO_RETRIEVAL"
    case genericRetrieval = "GENERIC_RETRIEVAL"
    case classification = "CLASSIFICATION"
    case clustering = "CLUSTERING"
}

public enum BedrockCohereEmbeddingInputType: String, Sendable, Equatable {
    case searchDocument = "search_document"
    case searchQuery = "search_query"
    case classification = "classification"
    case clustering = "clustering"
}

public enum BedrockEmbeddingTruncate: String, Sendable, Equatable {
    case none = "NONE"
    case start = "START"
    case end = "END"
}

public enum BedrockCohereOutputDimension: Int, Sendable, Equatable {
    case d256 = 256
    case d512 = 512
    case d1024 = 1024
    case d1536 = 1536
}

public struct BedrockEmbeddingProviderOptions: Sendable, Equatable {
    public var dimensions: BedrockEmbeddingDimensions?
    public var normalize: Bool?
    public var embeddingDimension: BedrockNovaEmbeddingDimension?
    public var embeddingPurpose: BedrockEmbeddingPurpose?
    public var inputType: BedrockCohereEmbeddingInputType?
    public var truncate: BedrockEmbeddingTruncate?
    public var outputDimension: BedrockCohereOutputDimension?

    public init(
        dimensions: BedrockEmbeddingDimensions? = nil,
        normalize: Bool? = nil,
        embeddingDimension: BedrockNovaEmbeddingDimension? = nil,
        embeddingPurpose: BedrockEmbeddingPurpose? = nil,
        inputType: BedrockCohereEmbeddingInputType? = nil,
        truncate: BedrockEmbeddingTruncate? = nil,
        outputDimension: BedrockCohereOutputDimension? = nil
    ) {
        self.dimensions = dimensions
        self.normalize = normalize
        self.embeddingDimension = embeddingDimension
        self.embeddingPurpose = embeddingPurpose
        self.inputType = inputType
        self.truncate = truncate
        self.outputDimension = outputDimension
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

                var embeddingDimension: BedrockNovaEmbeddingDimension? = nil
                if let rawEmbeddingDimension = object["embeddingDimension"], rawEmbeddingDimension != .null {
                    guard case .number(let number) = rawEmbeddingDimension,
                          let parsed = BedrockNovaEmbeddingDimension(rawValue: Int(number)),
                          Double(parsed.rawValue) == number else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "embeddingDimension must be one of 256, 384, 1024, 3072"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawEmbeddingDimension, cause: error))
                    }
                    embeddingDimension = parsed
                }

                var embeddingPurpose: BedrockEmbeddingPurpose? = nil
                if let rawEmbeddingPurpose = object["embeddingPurpose"], rawEmbeddingPurpose != .null {
                    guard case .string(let raw) = rawEmbeddingPurpose,
                          let parsed = BedrockEmbeddingPurpose(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "embeddingPurpose must be one of GENERIC_INDEX, TEXT_RETRIEVAL, IMAGE_RETRIEVAL, VIDEO_RETRIEVAL, DOCUMENT_RETRIEVAL, AUDIO_RETRIEVAL, GENERIC_RETRIEVAL, CLASSIFICATION, CLUSTERING"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawEmbeddingPurpose, cause: error))
                    }
                    embeddingPurpose = parsed
                }

                var inputType: BedrockCohereEmbeddingInputType? = nil
                if let rawInputType = object["inputType"], rawInputType != .null {
                    guard case .string(let raw) = rawInputType,
                          let parsed = BedrockCohereEmbeddingInputType(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "inputType must be one of search_document, search_query, classification, clustering"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawInputType, cause: error))
                    }
                    inputType = parsed
                }

                var truncate: BedrockEmbeddingTruncate? = nil
                if let rawTruncate = object["truncate"], rawTruncate != .null {
                    guard case .string(let raw) = rawTruncate,
                          let parsed = BedrockEmbeddingTruncate(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "truncate must be one of NONE, START, END"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawTruncate, cause: error))
                    }
                    truncate = parsed
                }

                var outputDimension: BedrockCohereOutputDimension? = nil
                if let rawOutputDimension = object["outputDimension"], rawOutputDimension != .null {
                    guard case .number(let number) = rawOutputDimension,
                          let parsed = BedrockCohereOutputDimension(rawValue: Int(number)),
                          Double(parsed.rawValue) == number else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "outputDimension must be one of 256, 512, 1024, 1536"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawOutputDimension, cause: error))
                    }
                    outputDimension = parsed
                }

                return .success(value: BedrockEmbeddingProviderOptions(
                    dimensions: dimensions,
                    normalize: normalize,
                    embeddingDimension: embeddingDimension,
                    embeddingPurpose: embeddingPurpose,
                    inputType: inputType,
                    truncate: truncate,
                    outputDimension: outputDimension
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
