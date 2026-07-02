import Foundation
import Testing
@testable import AISDKProvider

@Suite("Realtime V4 and Middleware Contracts")
struct RealtimeV4MiddlewareTests {
    @Test("RealtimeModelV4 exposes session, client, server, and factory contracts")
    func realtimeModelV4Surface() async throws {
        let session = RealtimeModelV4SessionConfig(
            instructions: "Stay brief",
            voice: "alloy",
            outputModalities: [.text, .audio],
            inputAudioFormat: .init(type: "pcm16", rate: 16_000),
            inputAudioTranscription: .init(model: "whisper-1", language: "en", prompt: "Names matter"),
            outputAudioTranscription: .init(model: "gpt-4o-mini-transcribe"),
            outputAudioFormat: .init(type: "opus"),
            turnDetection: .serverVAD(threshold: 0.45, silenceDurationMs: 500, prefixPaddingMs: 300),
            tools: [
                .init(
                    name: "lookup",
                    parameters: [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string"]
                        ]
                    ],
                    description: "Lookup facts"
                )
            ],
            providerOptions: ["openai": ["sessionMode": "beta"]]
        )

        #expect(session.outputModalities == [.text, .audio])
        #expect(session.inputAudioFormat == .init(type: "pcm16", rate: 16_000))
        #expect(session.inputAudioTranscription == .init(model: "whisper-1", language: "en", prompt: "Names matter"))
        #expect(session.turnDetection == .serverVAD(threshold: 0.45, silenceDurationMs: 500, prefixPaddingMs: 300))
        #expect(session.tools?.first?.type == "function")
        #expect(session.providerOptions?["openai"] == .object(["sessionMode": .string("beta")]))

        let factory = MockRealtimeFactoryV4()
        let token = try await factory.getToken(options: .init(
            model: "realtime-model",
            expiresAfterSeconds: 60,
            sessionConfig: session
        ))
        #expect(token.token == "factory-token:realtime-model")
        #expect(token.url == "wss://example.test/realtime")
        #expect(token.expiresAt == 60)

        let model = factory.realtimeModel(modelId: "realtime-model")
        #expect(model.specificationVersion == "v4")
        #expect(model.provider == "mock.realtime")
        #expect(model.modelId == "realtime-model")

        let secret = try await model.doCreateClientSecret(options: .init(expiresAfterSeconds: 120, sessionConfig: session))
        #expect(secret.token == "secret:realtime-model")
        #expect(secret.expiresAt == 120)

        let webSocket = try model.getWebSocketConfig(options: .init(token: secret.token, url: secret.url))
        #expect(webSocket.url == "wss://example.test/realtime?token=secret:realtime-model")
        #expect(webSocket.protocols == ["ai.realtime.v4"])

        let raw: JSONValue = [
            "type": "response.done",
            "response": ["id": "resp-1", "status": "completed"]
        ]
        let events = try model.parseServerEvent(raw: raw)
        #expect(events == [.responseDone(responseId: "resp-1", status: "completed", raw: raw)])

        let serialized = try await model.serializeClientEvent(.responseCreate(options: .init(
            modalities: ["text", "audio"],
            instructions: "Answer",
            metadata: ["trace": "t-1"]
        )))
        #expect(serialized == [
            "type": "response.create",
            "response": [
                "modalities": ["text", "audio"],
                "instructions": "Answer",
                "metadata": ["trace": "t-1"]
            ]
        ])

        let builtSession = try model.buildSessionConfig(session)
        #expect(builtSession == [
            "instructions": "Stay brief",
            "voice": "alloy",
            "modalities": ["text", "audio"],
            "input_audio_format": ["type": "pcm16", "rate": 16_000],
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.45,
                "silence_duration_ms": 500,
                "prefix_padding_ms": 300
            ],
            "provider_options": ["openai": ["sessionMode": "beta"]]
        ])

        #expect(try model.getHealthCheckResponse(raw: ["status": "ok"]) == ["status": "ok"])
    }

    @Test("LanguageModelV4Middleware wraps params and generated results")
    func languageModelV4MiddlewareSurface() async throws {
        let model = MockLanguageModelV4(modelId: "language")
        let middleware = LanguageModelV4Middleware(
            overrideProvider: { model in "\(model.provider).wrapped" },
            overrideModelId: { model in "\(model.modelId).wrapped" },
            overrideSupportedUrls: { _ in
                ["text/plain": [try NSRegularExpression(pattern: "https://example\\.test/files/.*")]]
            },
            transformParams: { type, params, _ in
                #expect(type == .generate)
                return LanguageModelV4CallOptions(
                    prompt: params.prompt,
                    maxOutputTokens: 42,
                    headers: ["x-v4": "1"],
                    reasoning: .minimal,
                    providerOptions: ["mock": ["transformed": true]]
                )
            },
            wrapGenerate: { doGenerate, _, params, _ in
                let base = try await doGenerate()
                return LanguageModelV4GenerateResult(
                    content: base.content + [.custom(.init(kind: "middleware", providerMetadata: ["mock": ["max": .number(Double(params.maxOutputTokens ?? 0))]]))],
                    finishReason: base.finishReason,
                    usage: base.usage,
                    warnings: [.other(message: "wrapped")]
                )
            },
            wrapStream: { _, doStream, _, _ in
                try await doStream()
            }
        )

        #expect(middleware.specificationVersion == "v4")
        #expect(middleware.overrideProvider?(model) == "mock.language.wrapped")
        #expect(middleware.overrideModelId?(model) == "language.wrapped")
        let overrideSupportedUrls = try #require(middleware.overrideSupportedUrls)
        #expect(try await overrideSupportedUrls(model)["text/plain"]?.first?.pattern == "https://example\\.test/files/.*")

        let baseOptions = LanguageModelV4CallOptions(prompt: [.system(content: "System", providerOptions: nil)])
        let transformLanguageParams = try #require(middleware.transformParams)
        let transformed = try await transformLanguageParams(.generate, baseOptions, model)
        #expect(transformed.maxOutputTokens == 42)
        #expect(transformed.reasoning == LanguageModelV4ReasoningEffort.minimal)
        #expect(transformed.providerOptions?["mock"]?["transformed"] == .bool(true))

        let wrapGenerate = try #require(middleware.wrapGenerate)
        let wrapped = try await wrapGenerate(
            { try await model.doGenerate(options: transformed) },
            { try await model.doStream(options: transformed) },
            transformed,
            model
        )
        #expect(wrapped.content.count == 2)
        #expect(wrapped.warnings == [.other(message: "wrapped")])

        let wrapStream = try #require(middleware.wrapStream)
        let stream = try await wrapStream(
            { try await model.doGenerate(options: transformed) },
            { try await model.doStream(options: transformed) },
            transformed,
            model
        )
        for try await _ in stream.stream {}
    }

    @Test("Embedding and image V4 middleware carry non-language hooks")
    func nonLanguageMiddlewareSurface() async throws {
        let embeddingModel = MockEmbeddingModelV4(modelId: "embed")
        let embeddingMiddleware = EmbeddingModelV4Middleware(
            overrideProvider: { "\($0.provider).wrapped" },
            overrideModelId: { "\($0.modelId).wrapped" },
            overrideMaxEmbeddingsPerCall: { _ in 8 },
            overrideSupportsParallelCalls: { _ in false },
            transformParams: { params, _ in
                EmbeddingModelV4CallOptions(
                    values: params.values + ["extra"],
                    providerOptions: ["mock": ["transformed": true]],
                    headers: ["x-embed": "1"]
                )
            },
            wrapEmbed: { doEmbed, _, _ in
                let base = try await doEmbed()
                return EmbeddingModelV4Result(
                    embeddings: base.embeddings + [[2, 3]],
                    usage: .init(tokens: 4),
                    warnings: [.unsupported(feature: "embedding-batch", details: nil)]
                )
            }
        )

        #expect(embeddingMiddleware.specificationVersion == "v4")
        #expect(embeddingMiddleware.overrideProvider?(embeddingModel) == "mock.embedding.wrapped")
        #expect(try await embeddingMiddleware.overrideMaxEmbeddingsPerCall?(embeddingModel) == 8)
        #expect(try await embeddingMiddleware.overrideSupportsParallelCalls?(embeddingModel) == false)

        let transformEmbeddingParams = try #require(embeddingMiddleware.transformParams)
        let embeddingOptions = try await transformEmbeddingParams(
            EmbeddingModelV4CallOptions(values: ["one"]),
            embeddingModel
        )
        #expect(embeddingOptions.values == ["one", "extra"])
        #expect(embeddingOptions.headers == ["x-embed": "1"])

        let wrapEmbed = try #require(embeddingMiddleware.wrapEmbed)
        let embedding = try await wrapEmbed(
            { try await embeddingModel.doEmbed(options: embeddingOptions) },
            embeddingOptions,
            embeddingModel
        )
        #expect(embedding.embeddings == [[0, 1], [2, 3]])
        #expect(embedding.usage == EmbeddingModelV4Usage(tokens: 4))
        #expect(embedding.warnings == [.unsupported(feature: "embedding-batch", details: nil)])

        let imageModel = MockImageModelV4(modelId: "image")
        let imageMiddleware = ImageModelV4Middleware(
            overrideProvider: { "\($0.provider).wrapped" },
            overrideModelId: { "\($0.modelId).wrapped" },
            overrideMaxImagesPerCall: { _ in .value(4) },
            transformParams: { params, _ in
                ImageModelV4CallOptions(
                    prompt: "\(params.prompt ?? "") vivid",
                    n: 2,
                    providerOptions: ["mock": ["transformed": true]],
                    headers: ["x-image": "1"]
                )
            },
            wrapGenerate: { doGenerate, _, _ in
                let base = try await doGenerate()
                return ImageModelV4GenerateResult(
                    images: .base64(["wrapped"]),
                    warnings: [.compatibility(feature: "image-wrapper", details: nil)],
                    response: base.response,
                    usage: .init(totalTokens: 1)
                )
            }
        )

        #expect(imageMiddleware.specificationVersion == "v4")
        #expect(imageMiddleware.overrideProvider?(imageModel) == "mock.image.wrapped")
        if case .value(let maxImages)? = imageMiddleware.overrideMaxImagesPerCall?(imageModel) {
            #expect(maxImages == 4)
        } else {
            Issue.record("overrideMaxImagesPerCall should return a value override")
        }

        let transformImageParams = try #require(imageMiddleware.transformParams)
        let imageOptions = try await transformImageParams(
            ImageModelV4CallOptions(prompt: "Draw", n: 1),
            imageModel
        )
        #expect(imageOptions.prompt == "Draw vivid")
        #expect(imageOptions.n == 2)
        #expect(imageOptions.headers == ["x-image": "1"])

        let wrapImageGenerate = try #require(imageMiddleware.wrapGenerate)
        let image = try await wrapImageGenerate(
            { try await imageModel.doGenerate(options: imageOptions) },
            imageOptions,
            imageModel
        )
        #expect(image.images == ImageModelV4GeneratedImages.base64(["wrapped"]))
        #expect(image.usage == ImageModelV4Usage(totalTokens: 1))
        #expect(image.warnings == [.compatibility(feature: "image-wrapper", details: nil)])
    }
}

private struct MockRealtimeFactoryV4: RealtimeFactoryV4 {
    func realtimeModel(modelId: String) -> any RealtimeModelV4 {
        MockRealtimeModelV4(modelId: modelId)
    }

    func getToken(options: RealtimeFactoryV4GetTokenOptions) async throws -> RealtimeFactoryV4GetTokenResult {
        RealtimeFactoryV4GetTokenResult(
            token: "factory-token:\(options.model)",
            url: "wss://example.test/realtime",
            expiresAt: options.expiresAfterSeconds
        )
    }
}

private struct MockRealtimeModelV4: RealtimeModelV4 {
    let provider = "mock.realtime"
    let modelId: String

    func doCreateClientSecret(options: RealtimeModelV4ClientSecretOptions) async throws -> RealtimeModelV4ClientSecretResult {
        RealtimeModelV4ClientSecretResult(
            token: "secret:\(modelId)",
            url: "wss://example.test/realtime",
            expiresAt: options.expiresAfterSeconds
        )
    }

    func getWebSocketConfig(options: RealtimeModelV4WebSocketOptions) throws -> RealtimeModelV4WebSocketConfig {
        RealtimeModelV4WebSocketConfig(
            url: "\(options.url)?token=\(options.token)",
            protocols: ["ai.realtime.v4"]
        )
    }

    func parseServerEvent(raw: JSONValue) throws -> [RealtimeModelV4ServerEvent] {
        guard case .object(let object) = raw else {
            return [.custom(rawType: "unknown", raw: raw)]
        }

        if
            case .string("response.done")? = object["type"],
            case .object(let response)? = object["response"],
            case .string(let id)? = response["id"],
            case .string(let status)? = response["status"]
        {
            return [.responseDone(responseId: id, status: status, raw: raw)]
        }

        if case .string(let type)? = object["type"] {
            return [.custom(rawType: type, raw: raw)]
        }

        return [.custom(rawType: "unknown", raw: raw)]
    }

    func serializeClientEvent(_ event: RealtimeModelV4ClientEvent) async throws -> JSONValue {
        switch event {
        case .responseCreate(let options):
            var response: [String: JSONValue] = [:]
            if let modalities = options?.modalities {
                response["modalities"] = .array(modalities.map(JSONValue.string))
            }
            if let instructions = options?.instructions {
                response["instructions"] = .string(instructions)
            }
            if let metadata = options?.metadata {
                response["metadata"] = .object(metadata)
            }
            return ["type": "response.create", "response": .object(response)]
        case .responseCancel:
            return ["type": "response.cancel"]
        case .sessionUpdate(let config):
            return ["type": "session.update", "session": try buildSessionConfig(config)]
        case .inputAudioAppend(let audio):
            return ["type": "input_audio_buffer.append", "audio": .string(audio)]
        case .inputAudioCommit:
            return ["type": "input_audio_buffer.commit"]
        case .inputAudioClear:
            return ["type": "input_audio_buffer.clear"]
        case .conversationItemCreate(let item):
            return ["type": "conversation.item.create", "item": encodeConversationItem(item)]
        case .conversationItemTruncate(let itemId, let contentIndex, let audioEndMs):
            return [
                "type": "conversation.item.truncate",
                "item_id": .string(itemId),
                "content_index": .number(Double(contentIndex)),
                "audio_end_ms": .number(Double(audioEndMs))
            ]
        }
    }

    func buildSessionConfig(_ config: RealtimeModelV4SessionConfig) throws -> JSONValue {
        var session: [String: JSONValue] = [:]
        if let instructions = config.instructions {
            session["instructions"] = .string(instructions)
        }
        if let voice = config.voice {
            session["voice"] = .string(voice)
        }
        if let modalities = config.outputModalities {
            session["modalities"] = .array(modalities.map { .string($0.rawValue) })
        }
        if let inputAudioFormat = config.inputAudioFormat {
            session["input_audio_format"] = encodeAudioFormat(inputAudioFormat)
        }
        if let turnDetection = config.turnDetection {
            session["turn_detection"] = encodeTurnDetection(turnDetection)
        }
        if let providerOptions = config.providerOptions {
            session["provider_options"] = .object(providerOptions)
        }
        return .object(session)
    }

    func getHealthCheckResponse(raw: JSONValue) throws -> JSONValue? {
        raw
    }

    private func encodeAudioFormat(_ format: RealtimeModelV4SessionConfig.AudioFormat) -> JSONValue {
        var object: [String: JSONValue] = ["type": .string(format.type)]
        if let rate = format.rate {
            object["rate"] = .number(Double(rate))
        }
        return .object(object)
    }

    private func encodeTurnDetection(_ turnDetection: RealtimeModelV4SessionConfig.TurnDetection) -> JSONValue {
        switch turnDetection {
        case .serverVAD(let threshold, let silenceDurationMs, let prefixPaddingMs):
            return encodeVad("server_vad", threshold: threshold, silenceDurationMs: silenceDurationMs, prefixPaddingMs: prefixPaddingMs)
        case .semanticVAD(let threshold, let silenceDurationMs, let prefixPaddingMs):
            return encodeVad("semantic_vad", threshold: threshold, silenceDurationMs: silenceDurationMs, prefixPaddingMs: prefixPaddingMs)
        case .disabled:
            return ["type": "none"]
        }
    }

    private func encodeVad(
        _ type: String,
        threshold: Double?,
        silenceDurationMs: Int?,
        prefixPaddingMs: Int?
    ) -> JSONValue {
        var object: [String: JSONValue] = ["type": .string(type)]
        if let threshold {
            object["threshold"] = .number(threshold)
        }
        if let silenceDurationMs {
            object["silence_duration_ms"] = .number(Double(silenceDurationMs))
        }
        if let prefixPaddingMs {
            object["prefix_padding_ms"] = .number(Double(prefixPaddingMs))
        }
        return .object(object)
    }

    private func encodeConversationItem(_ item: RealtimeModelV4ConversationItem) -> JSONValue {
        switch item {
        case .textMessage(let text):
            return ["type": "message", "content": [["type": "input_text", "text": .string(text)]]]
        case .audioMessage(let audio):
            return ["type": "message", "content": [["type": "input_audio", "audio": .string(audio)]]]
        case .functionCallOutput(let callId, let name, let output):
            var object: [String: JSONValue] = [
                "type": "function_call_output",
                "call_id": .string(callId),
                "output": .string(output)
            ]
            if let name {
                object["name"] = .string(name)
            }
            return .object(object)
        }
    }
}

private struct MockLanguageModelV4: LanguageModelV4 {
    let provider = "mock.language"
    let modelId: String

    func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        LanguageModelV4GenerateResult(
            content: [.text(.init(text: "ok"))],
            finishReason: .init(unified: .stop),
            usage: .init()
        )
    }

    func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        LanguageModelV4StreamResult(stream: AsyncThrowingStream { continuation in
            continuation.finish()
        })
    }
}

private struct MockEmbeddingModelV4: EmbeddingModelV4 {
    let provider = "mock.embedding"
    let modelId: String

    var maxEmbeddingsPerCall: Int? {
        get async throws { nil }
    }

    var supportsParallelCalls: Bool {
        get async throws { true }
    }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        EmbeddingModelV4Result(embeddings: [[0, 1]])
    }
}

private struct MockImageModelV4: ImageModelV4 {
    let provider = "mock.image"
    let modelId: String
    let maxImagesPerCall: ImageModelV4MaxImagesPerCall = .default

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        ImageModelV4GenerateResult(
            images: .base64(["base"]),
            response: .init(timestamp: Date(timeIntervalSince1970: 0), modelId: modelId)
        )
    }
}
