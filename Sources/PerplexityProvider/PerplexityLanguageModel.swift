import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/perplexity-language-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class PerplexityLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let generateId: @Sendable () -> String
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private let modelIdentifier: PerplexityLanguageModelId
    private let config: Config

    init(modelId: PerplexityLanguageModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public let specificationVersion: String = "v3"
    public var provider: String { "perplexity" }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options, stream: false)

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: perplexityFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: perplexityResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw APICallError(
                message: "No choices returned from Perplexity",
                url: "\(config.baseURL)/chat/completions",
                requestBodyValues: prepared.body
            )
        }

        var content: [LanguageModelV3Content] = []
        if !choice.message.content.isEmpty {
            content.append(.text(LanguageModelV3Text(text: choice.message.content)))
        }

        if let citations = response.value.citations {
            for url in citations {
                content.append(.source(.url(id: config.generateId(), url: url, title: nil, providerMetadata: nil)))
            }
        }

        let usage = LanguageModelV3Usage(
            inputTokens: response.value.usage?.promptTokens,
            outputTokens: response.value.usage?.completionTokens,
            totalTokens: response.value.usage?.totalTokens
        )

        let metadata = perplexityResponseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)
        let providerMetadata = makePerplexityProviderMetadata(images: response.value.images, usage: response.value.usage)

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: mapPerplexityFinishReason(choice.finishReason),
            usage: usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: metadata.id,
                timestamp: metadata.timestamp,
                modelId: metadata.modelId,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options, stream: true)

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: perplexityFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: perplexityChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var metadataAccumulator = PerplexityStreamingMetadata()
                var isFirstChunk = true
                var isActiveText = false

                do {
                    for try await parseResult in response.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .error
                            continuation.yield(.error(error: .string(String(describing: error))))
                            continue

                        case .success(let chunk, _):
                            if isFirstChunk {
                                isFirstChunk = false
                                let metadata = perplexityResponseMetadata(id: chunk.id, model: chunk.model, created: chunk.created)
                                continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))

                                chunk.citations?.forEach { url in
                                    continuation.yield(.source(.url(id: config.generateId(), url: url, title: nil, providerMetadata: nil)))
                                }
                            }

                            if let usageData = chunk.usage {
                                usage = LanguageModelV3Usage(
                                    inputTokens: usageData.promptTokens,
                                    outputTokens: usageData.completionTokens,
                                    totalTokens: usageData.totalTokens
                                )
                                metadataAccumulator.citationTokens = usageData.citationTokens
                                metadataAccumulator.numSearchQueries = usageData.numSearchQueries
                            }

                            if let images = chunk.images, !images.isEmpty {
                                metadataAccumulator.images = images
                            }

                            if let choice = chunk.choices.first {
                                if let finish = choice.finishReason {
                                    finishReason = mapPerplexityFinishReason(finish)
                                }

                                if let delta = choice.delta, let text = delta.content, !text.isEmpty {
                                    if !isActiveText {
                                        isActiveText = true
                                        continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    }

                                    continuation.yield(.textDelta(id: "0", delta: text, providerMetadata: nil))
                                }
                            }
                        }
                    }

                    if isActiveText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }

                    continuation.yield(
                        .finish(
                            finishReason: finishReason,
                            usage: usage,
                            providerMetadata: metadataAccumulator.providerMetadata()
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3StreamResponseInfo(headers: response.responseHeaders)
        )
    }

    private func prepareRequest(options: LanguageModelV3CallOptions, stream: Bool) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }
        if options.stopSequences != nil {
            warnings.append(.unsupported(feature: "stopSequences", details: nil))
        }
        if options.seed != nil {
            warnings.append(.unsupported(feature: "seed", details: nil))
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue)
        ]

        if let frequencyPenalty = options.frequencyPenalty {
            body["frequency_penalty"] = .number(frequencyPenalty)
        }
        if let maxTokens = options.maxOutputTokens {
            body["max_tokens"] = .number(Double(maxTokens))
        }
        if let presencePenalty = options.presencePenalty {
            body["presence_penalty"] = .number(presencePenalty)
        }
        if let temperature = options.temperature {
            body["temperature"] = .number(temperature)
        }
        if let topK = options.topK {
            body["top_k"] = .number(Double(topK))
        }
        if let topP = options.topP {
            body["top_p"] = .number(topP)
        }

        if case let .json(schema, _, _) = options.responseFormat {
            var schemaObject: [String: JSONValue] = [:]
            if let schema {
                schemaObject["schema"] = schema
            }
            body["response_format"] = .object([
                "type": .string("json_schema"),
                "json_schema": .object(schemaObject)
            ])
        }

        if let providerOptions = options.providerOptions?["perplexity"] {
            for (key, value) in providerOptions {
                body[key] = value
            }
        }

        let messages = try convertToPerplexityMessages(options.prompt)
        body["messages"] = try encodeMessages(messages)

        if stream {
            body["stream"] = .bool(true)
        }

        return PreparedRequest(body: body, warnings: warnings)
    }
}

// MARK: - Provider Metadata

private func makePerplexityProviderMetadata(images: [PerplexityImage]?, usage: PerplexityUsage?) -> SharedV3ProviderMetadata {
    let imagesValue: JSONValue
    if let images, !images.isEmpty {
        imagesValue = .array(images.map { image in
            .object([
                "imageUrl": .string(image.imageURL),
                "originUrl": .string(image.originURL),
                "height": .number(Double(image.height)),
                "width": .number(Double(image.width))
            ])
        })
    } else {
        imagesValue = .null
    }

    let usageValue: JSONValue = .object([
        "citationTokens": usage?.citationTokens.map { .number(Double($0)) } ?? .null,
        "numSearchQueries": usage?.numSearchQueries.map { .number(Double($0)) } ?? .null
    ])

    return [
        "perplexity": [
            "images": imagesValue,
            "usage": usageValue
        ]
    ]
}

private struct PerplexityStreamingMetadata {
    var citationTokens: Int?
    var numSearchQueries: Int?
    var images: [PerplexityImage]?

    func providerMetadata() -> SharedV3ProviderMetadata {
        makePerplexityProviderMetadata(images: images, usage: PerplexityUsage(
            promptTokens: nil,
            completionTokens: nil,
            totalTokens: nil,
            citationTokens: citationTokens,
            numSearchQueries: numSearchQueries
        ))
    }
}

// MARK: - Encoding Helpers

private func encodeMessages(_ messages: [PerplexityMessage]) throws -> JSONValue {
    let encoder = JSONEncoder()
    let data = try encoder.encode(messages)
    let raw = try JSONSerialization.jsonObject(with: data, options: [])
    return try jsonValue(from: raw)
}

private func perplexityResponseMetadata(id: String?, model: String?, created: Double?) -> (id: String?, modelId: String?, timestamp: Date?) {
    let timestamp = created.map { Date(timeIntervalSince1970: $0) }
    return (id: id, modelId: model, timestamp: timestamp)
}

// MARK: - Schemas & Models

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

private let perplexityResponseSchema = FlexibleSchema(
    Schema<PerplexityResponse>.codable(
        PerplexityResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let perplexityChunkSchema = FlexibleSchema(
    Schema<PerplexityStreamChunk>.codable(
        PerplexityStreamChunk.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private struct PerplexityResponse: Codable, Sendable {
    struct Choice: Codable, Sendable {
        struct Message: Codable, Sendable {
            let role: String
            let content: String
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let citations: [String]?
    let images: [PerplexityImage]?
    let usage: PerplexityUsage?
}

private struct PerplexityStreamChunk: Codable, Sendable {
    struct Choice: Codable, Sendable {
        struct Delta: Codable, Sendable {
            let role: String
            let content: String?
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let citations: [String]?
    let images: [PerplexityImage]?
    let usage: PerplexityUsage?
}

private struct PerplexityUsage: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let citationTokens: Int?
    let numSearchQueries: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case citationTokens = "citation_tokens"
        case numSearchQueries = "num_search_queries"
    }
}

private struct PerplexityImage: Codable, Sendable {
    let imageURL: String
    let originURL: String
    let height: Int
    let width: Int

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case originURL = "origin_url"
        case height
        case width
    }
}

private extension ParseJSONResult where Output == PerplexityStreamChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}
