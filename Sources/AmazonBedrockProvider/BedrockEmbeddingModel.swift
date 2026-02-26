import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-embedding-model.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

struct BedrockEmbeddingConfig: Sendable {
    let baseURL: @Sendable () -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
}

private let bedrockEmbeddingResponseSchema = FlexibleSchema(
    Schema<JSONValue>.codable(
        JSONValue.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public final class BedrockEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    private let modelIdentifier: BedrockEmbeddingModelId
    private let config: BedrockEmbeddingConfig

    init(modelId: BedrockEmbeddingModelId, config: BedrockEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }
    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 1 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        if options.values.count > 1 {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: 1,
                values: options.values.map { $0 as Any }
            )
        }

        let bedrockOptions = try await parseProviderOptions(
            provider: "bedrock",
            providerOptions: options.providerOptions,
            schema: bedrockEmbeddingProviderOptionsSchema
        )

        guard let value = options.values.first else {
            return EmbeddingModelV3DoEmbedResult(embeddings: [], usage: nil, providerMetadata: nil, response: nil)
        }

        let rawModelId = modelIdentifier.rawValue
        let optionsValue = bedrockOptions ?? BedrockEmbeddingProviderOptions()

        let isNovaModel = rawModelId.hasPrefix("amazon.nova-") && rawModelId.contains("embed")
        let isCohereModel = rawModelId.hasPrefix("cohere.embed-")

        let body: JSONValue
        if isNovaModel {
            let purpose = optionsValue.embeddingPurpose?.rawValue ?? "GENERIC_INDEX"
            let dimension = optionsValue.embeddingDimension?.rawValue ?? 1024
            let truncation = optionsValue.truncate?.rawValue ?? "END"

            body = .object([
                "taskType": .string("SINGLE_EMBEDDING"),
                "singleEmbeddingParams": .object([
                    "embeddingPurpose": .string(purpose),
                    "embeddingDimension": .number(Double(dimension)),
                    "text": .object([
                        "truncationMode": .string(truncation),
                        "value": .string(value)
                    ])
                ])
            ])
        } else if isCohereModel {
            var payload: [String: JSONValue] = [
                "input_type": .string(optionsValue.inputType?.rawValue ?? "search_query"),
                "texts": .array([.string(value)])
            ]

            if let truncate = optionsValue.truncate {
                payload["truncate"] = .string(truncate.rawValue)
            }

            if let outputDimension = optionsValue.outputDimension {
                payload["output_dimension"] = .number(Double(outputDimension.rawValue))
            }

            body = .object(payload)
        } else {
            var payload: [String: JSONValue] = [
                "inputText": .string(value)
            ]

            if let dimensions = optionsValue.dimensions {
                payload["dimensions"] = .number(Double(dimensions.rawValue))
            }

            if let normalize = optionsValue.normalize {
                payload["normalize"] = .bool(normalize)
            }

            body = .object(payload)
        }

        let url = "\(config.baseURL())/model/\(bedrockEncodeURIComponent(rawModelId))/invoke"
        let headers = mergeHeaders(base: config.headers(), overrides: options.headers)

        let response = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: body,
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let (embedding, tokens) = try parseEmbeddingResponse(
            response.value,
            isNovaModel: isNovaModel,
            isCohereModel: isCohereModel
        )

        let usage = tokens.map(EmbeddingModelV3Usage.init(tokens:))

        let responseInfo = EmbeddingModelV3ResponseInfo(
            headers: response.responseHeaders,
            body: response.rawValue
        )

        return EmbeddingModelV3DoEmbedResult(
            embeddings: [embedding],
            usage: usage,
            providerMetadata: nil,
            response: responseInfo,
            warnings: []
        )
    }

    private func mergeHeaders(base: [String: String?], overrides: [String: String]?) -> [String: String] {
        let merged = combineHeaders(
            base,
            overrides?.mapValues { Optional($0) }
        )
        return merged.compactMapValues { $0 }
    }

}

private func parseEmbeddingResponse(
    _ value: JSONValue,
    isNovaModel: Bool,
    isCohereModel: Bool
) throws -> (embedding: [Double], tokens: Int?) {
    let foundationValue = jsonValueToFoundation(value)

    guard case .object(let dict) = value else {
        throw TypeValidationError.wrap(
            value: foundationValue,
            cause: BedrockEmbeddingResponseShapeMismatchError(
                message: "Expected object embedding response."
            )
        )
    }

    // Titan-style response: { embedding: number[], inputTextTokenCount: number }
    if let embeddingValue = dict["embedding"],
       let embedding = doubleArray(from: embeddingValue),
       let tokenValue = dict["inputTextTokenCount"],
       let tokens = intValue(tokenValue) {
        return (embedding, tokens)
    }

    if let embeddingsValue = dict["embeddings"] {
        switch embeddingsValue {
        case .array(let array):
            if array.isEmpty {
                if isNovaModel {
                    let tokens = dict["inputTokenCount"].flatMap(intValue) ?? 0
                    return ([], tokens)
                }

                if isCohereModel {
                    return ([], nil)
                }

                throw TypeValidationError.wrap(
                    value: foundationValue,
                    cause: BedrockEmbeddingResponseShapeMismatchError(
                        message: "Unexpected embedding response shape."
                    )
                )
            }

            let first = array[0]

            // Nova-style response: embeddings: [{ embeddingType: string, embedding: number[] }], inputTokenCount?: number
            if case .object(let firstObject) = first,
               case .some(.string) = firstObject["embeddingType"],
               let embeddingValue = firstObject["embedding"],
               let embedding = doubleArray(from: embeddingValue) {
                let tokens = dict["inputTokenCount"].flatMap(intValue) ?? 0
                return (embedding, tokens)
            }

            // Cohere v3-style response: embeddings: [number[]]
            if let embedding = doubleArray(from: first) {
                return (embedding, nil)
            }

        case .object(let object):
            // Cohere v4-style response: embeddings: { float: number[][] }
            if let floatValue = object["float"] {
                guard case .array(let floatEmbeddings) = floatValue else {
                    throw TypeValidationError.wrap(
                        value: foundationValue,
                        cause: BedrockEmbeddingResponseShapeMismatchError(
                            message: "Invalid embeddings.float response shape."
                        )
                    )
                }

                guard let first = floatEmbeddings.first else {
                    return ([], nil)
                }

                guard let embedding = doubleArray(from: first) else {
                    throw TypeValidationError.wrap(
                        value: foundationValue,
                        cause: BedrockEmbeddingResponseShapeMismatchError(
                            message: "Invalid embeddings.float[0] response shape."
                        )
                    )
                }

                return (embedding, nil)
            }
        default:
            break
        }
    }

    throw TypeValidationError.wrap(
        value: foundationValue,
        cause: BedrockEmbeddingResponseShapeMismatchError(
            message: "Unexpected embedding response shape."
        )
    )
}

private struct BedrockEmbeddingResponseShapeMismatchError: Error, CustomStringConvertible, Sendable {
    let message: String

    var description: String { message }
}

private func doubleArray(from value: JSONValue) -> [Double]? {
    guard case .array(let array) = value else { return nil }
    var numbers: [Double] = []
    numbers.reserveCapacity(array.count)

    for element in array {
        guard case .number(let number) = element else {
            return nil
        }
        numbers.append(number)
    }

    return numbers
}

private func intValue(_ value: JSONValue) -> Int? {
    switch value {
    case .number(let number):
        return Int(number)
    case .string(let text):
        return Int(text)
    default:
        return nil
    }
}
