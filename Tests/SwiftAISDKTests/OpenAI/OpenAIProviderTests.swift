import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private func makeEmbeddingResponseData() -> Data {
    let json: [String: Any] = [
        "object": "list",
        "data": [
            [
                "object": "embedding",
                "index": 0,
                "embedding": [0.1, 0.2]
            ]
        ],
        "model": "text-embedding-3-small",
        "usage": ["prompt_tokens": 1, "total_tokens": 1]
    ]
    return try! JSONSerialization.data(withJSONObject: json)
}

private let openAIV4Prompt: LanguageModelV4Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

@Suite("OpenAIProvider")
struct OpenAIProviderTests {
    actor URLCapture {
        private(set) var url: String?
        func store(_ url: String?) { self.url = url }
        func current() -> String? { url }
    }

    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func makeFetch(capture: URLCapture) -> FetchFunction {
        let data = makeEmbeddingResponseData()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return { request in
            await capture.store(request.url?.absoluteString)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }

    private func makeFailingFetch(capture: URLCapture) -> FetchFunction {
        let responseData = try! JSONSerialization.data(withJSONObject: [
            "error": [
                "message": "test error",
                "type": "invalid_request_error",
                "param": NSNull(),
                "code": "test_error"
            ]
        ])

        return { request in
            await capture.store(request.url?.absoluteString)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }
    }

    private func makeEmbeddingFetch(capture: RequestCapture) -> FetchFunction {
        let data = makeEmbeddingResponseData()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }

    @Suite("baseURL configuration", .serialized)
    struct BaseURLConfigurationTests {
        @Test("missing API key throws LoadAPIKeyError on first request")
        func testMissingAPIKeyThrowsAtRequestTime() async throws {
            let original = getenv("OPENAI_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("OPENAI_API_KEY", original, 1)
                } else {
                    unsetenv("OPENAI_API_KEY")
                }
            }

            unsetenv("OPENAI_API_KEY")
            let capture = URLCapture()
            let provider = try createOpenAIProvider(
                settings: OpenAIProviderSettings(fetch: makeFetch(capture: capture))
            )

            do {
                _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
                    options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("OpenAI API key is missing"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.current() == nil)
        }

        // Port of openai-provider.test.ts: "uses the default OpenAI base URL when not provided"
        @Test("uses default OpenAI base URL")
        func testUsesDefaultBaseURL() async throws {
            let original = getenv("OPENAI_BASE_URL").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("OPENAI_BASE_URL", original, 1)
                } else {
                    unsetenv("OPENAI_BASE_URL")
                }
            }

            unsetenv("OPENAI_BASE_URL")
            let capture = URLCapture()
            let provider = try createOpenAIProvider(
                settings: OpenAIProviderSettings(apiKey: "test-api-key", fetch: makeFetch(capture: capture))
            )
            _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
                options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
            )
            let url = await capture.current()
            #expect(url == "https://api.openai.com/v1/embeddings")
        }

        // Port of openai-provider.test.ts: "uses OPENAI_BASE_URL when set"
        @Test("uses OPENAI_BASE_URL when set")
        func testUsesEnvironmentBaseURL() async throws {
            let original = getenv("OPENAI_BASE_URL").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("OPENAI_BASE_URL", original, 1)
                } else {
                    unsetenv("OPENAI_BASE_URL")
                }
            }

            setenv("OPENAI_BASE_URL", "https://proxy.openai.example/v1/", 1)
            let capture = URLCapture()
            let provider = try createOpenAIProvider(
                settings: OpenAIProviderSettings(apiKey: "test-api-key", fetch: makeFetch(capture: capture))
            )
            _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
                options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
            )
            let url = await capture.current()
            #expect(url == "https://proxy.openai.example/v1/embeddings")
        }

        // Port of openai-provider.test.ts: "prefers the baseURL option over OPENAI_BASE_URL"
        @Test("prefers baseURL option over environment")
        func testPrefersExplicitBaseURL() async throws {
            let original = getenv("OPENAI_BASE_URL").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("OPENAI_BASE_URL", original, 1)
                } else {
                    unsetenv("OPENAI_BASE_URL")
                }
            }

            setenv("OPENAI_BASE_URL", "https://env.openai.example/v1", 1)
            let capture = URLCapture()
            let provider = try createOpenAIProvider(
                settings: OpenAIProviderSettings(
                    baseURL: "https://option.openai.example/v1/",
                    apiKey: "test-api-key",
                    fetch: makeFetch(capture: capture))
            )
            _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
                options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
            )
            let url = await capture.current()
            #expect(url == "https://option.openai.example/v1/embeddings")
        }

        private func makeFetch(capture: URLCapture) -> FetchFunction {
            let data = makeEmbeddingResponseData()
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            return { request in
                await capture.store(request.url?.absoluteString)
                return FetchResponse(body: .data(data), urlResponse: response)
            }
        }
    }

    @Test("embeddingModel String alias creates embedding model")
    func embeddingModelStringAliasCreatesEmbeddingModel() throws {
        let provider = try createOpenAIProvider(
            settings: OpenAIProviderSettings(apiKey: "test-api-key")
        )

        let model = try provider.embeddingModel(modelId: "text-embedding-3-small")

        #expect(model.provider == "openai.embedding")
        #expect(model.modelId == "text-embedding-3-small")
    }

    @Test("typed embeddingModel alias matches embedding alias")
    func typedEmbeddingModelAliasMatchesEmbeddingAlias() throws {
        let provider = try createOpenAIProvider(
            settings: OpenAIProviderSettings(apiKey: "test-api-key")
        )

        let typedModel = provider.embeddingModel(OpenAIEmbeddingModelId(rawValue: "text-embedding-3-small"))
        let embeddingAliasModel = provider.embedding(OpenAIEmbeddingModelId(rawValue: "text-embedding-3-small"))

        #expect(typedModel.provider == "openai.embedding")
        #expect(typedModel.modelId == "text-embedding-3-small")
        #expect(embeddingAliasModel.provider == "openai.embedding")
        #expect(embeddingAliasModel.modelId == "text-embedding-3-small")
    }

    @Test("createOpenAI exposes upstream V4 provider surface")
    func createOpenAIExposesV4ProviderSurface() throws {
        let provider = try createOpenAI(settings: .init(apiKey: "test-api-key", name: "custom-openai"))

        #expect(provider.specificationVersion == "v4")

        let languageModel = try provider.languageModel(modelId: "gpt-5")
        #expect(languageModel.specificationVersion == "v4")
        #expect(languageModel.provider == "custom-openai.responses")
        #expect(languageModel.modelId == "gpt-5")

        #expect(provider.responses("gpt-5").provider == "custom-openai.responses")
        #expect(provider.chat("gpt-5").provider == "custom-openai.chat")
        let completionModel: OpenAICompletionLanguageModelV4 = provider.completion("gpt-3.5-turbo-instruct")
        #expect(completionModel.specificationVersion == "v4")
        #expect(completionModel.provider == "custom-openai.completion")
        #expect(provider.embedding("text-embedding-3-small").provider == "custom-openai.embedding")
        #expect(provider.textEmbedding("text-embedding-3-small").provider == "custom-openai.embedding")
        let imageModel = provider.image("gpt-image-1")
        #expect(imageModel.specificationVersion == "v4")
        #expect(imageModel.provider == "custom-openai.image")
        let transcriptionModel: OpenAITranscriptionModelV4 = provider.transcription("whisper-1")
        #expect(transcriptionModel.specificationVersion == "v4")
        #expect(transcriptionModel.provider == "custom-openai.transcription")
        let speechModel = provider.speech("tts-1")
        #expect(speechModel.specificationVersion == "v4")
        #expect(speechModel.provider == "custom-openai.speech")

        let files = try #require(try provider.files())
        let skills = try #require(try provider.skills())
        #expect(files.specificationVersion == "v4")
        #expect(files.provider == "custom-openai.files")
        #expect(skills.specificationVersion == "v4")
        #expect(skills.provider == "custom-openai.skills")

        let realtimeModel = provider.experimental_realtime.realtimeModel(modelId: "gpt-realtime")
        #expect(realtimeModel.specificationVersion == "v4")
        #expect(realtimeModel.provider == "custom-openai.realtime")
    }

    @Test("createOpenAI V4 routes default, chat, and embedding calls like upstream")
    func createOpenAIV4RoutesRequestsLikeUpstream() async throws {
        do {
            let capture = URLCapture()
            let provider = try createOpenAI(settings: .init(
                baseURL: "https://proxy.openai.example/v1/",
                apiKey: "test-api-key",
                fetch: makeFailingFetch(capture: capture)
            ))
            let model = try provider("gpt-4o-mini")
            do {
                _ = try await model.doGenerate(options: .init(prompt: openAIV4Prompt))
            } catch {}

            #expect(await capture.current() == "https://proxy.openai.example/v1/responses")
        }

        do {
            let capture = URLCapture()
            let provider = try createOpenAI(settings: .init(
                baseURL: "https://proxy.openai.example/v1/",
                apiKey: "test-api-key",
                fetch: makeFailingFetch(capture: capture)
            ))
            do {
                _ = try await provider.chat("gpt-4o-mini").doGenerate(options: .init(prompt: openAIV4Prompt))
            } catch {}

            #expect(await capture.current() == "https://proxy.openai.example/v1/chat/completions")
        }

        do {
            let capture = URLCapture()
            let provider = try createOpenAI(settings: .init(
                baseURL: "https://proxy.openai.example/v1/",
                apiKey: "test-api-key",
                fetch: makeFailingFetch(capture: capture)
            ))
            do {
                _ = try await provider.completion("gpt-3.5-turbo-instruct").doGenerate(options: .init(prompt: openAIV4Prompt))
            } catch {}

            #expect(await capture.current() == "https://proxy.openai.example/v1/completions")
        }

        do {
            let capture = URLCapture()
            let provider = try createOpenAI(settings: .init(
                baseURL: "https://proxy.openai.example/v1/",
                apiKey: "test-api-key",
                fetch: makeFailingFetch(capture: capture)
            ))
            do {
                _ = try await provider.embedding("text-embedding-3-small").doEmbed(options: .init(values: ["hello"]))
            } catch {}

            #expect(await capture.current() == "https://proxy.openai.example/v1/embeddings")
        }

        do {
            let capture = URLCapture()
            let provider = try createOpenAI(settings: .init(
                baseURL: "https://proxy.openai.example/v1/",
                apiKey: "test-api-key",
                fetch: makeFailingFetch(capture: capture)
            ))
            do {
                _ = try await provider.transcription("whisper-1").doGenerate(
                    options: .init(audio: .binary(Data("audio".utf8)), mediaType: "audio/wav")
                )
            } catch {}

            #expect(await capture.current() == "https://proxy.openai.example/v1/audio/transcriptions")
        }

        do {
            let capture = URLCapture()
            let provider = try createOpenAI(settings: .init(
                baseURL: "https://proxy.openai.example/v1/",
                apiKey: "test-api-key",
                fetch: makeFailingFetch(capture: capture)
            ))
            do {
                _ = try await provider.speech("tts-1").doGenerate(options: .init(text: "hello"))
            } catch {}

            #expect(await capture.current() == "https://proxy.openai.example/v1/audio/speech")
        }
    }

    @Test("createOpenAI V4 applies auth, organization, project, custom headers, and user-agent like upstream")
    func createOpenAIV4AppliesProviderHeadersLikeUpstream() async throws {
        let capture = RequestCapture()
        let provider = try createOpenAI(settings: .init(
            apiKey: "base-api-key",
            organization: "base-organization",
            project: "base-project",
            headers: [
                "authorization": "Bearer custom-api-key",
                "openai-organization": "custom-organization",
                "openai-project": "custom-project",
                "x-custom-header": "custom-header-value",
                "user-agent": "Client/1.0"
            ],
            fetch: makeEmbeddingFetch(capture: capture)
        ))

        _ = try await provider.embedding("text-embedding-3-small").doEmbed(options: .init(values: ["hello"]))

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })

        #expect(normalizedHeaders["authorization"] == "Bearer custom-api-key")
        #expect(normalizedHeaders["openai-organization"] == "custom-organization")
        #expect(normalizedHeaders["openai-project"] == "custom-project")
        #expect(normalizedHeaders["x-custom-header"] == "custom-header-value")
        #expect(normalizedHeaders["user-agent"]?.contains("Client/1.0") == true)
        #expect(normalizedHeaders["user-agent"]?.contains("ai-sdk/openai/") == true)
        #expect(normalizedHeaders["user-agent"]?.contains("ai-sdk/provider-utils/") == true)
    }

    @Test("OpenAI factories reject empty baseURL at creation")
    func openAIFactoriesRejectEmptyBaseURLAtCreation() {
        for createProvider in [
            { try createOpenAIProvider(settings: .init(baseURL: "")) as Any },
            { try createOpenAI(settings: .init(baseURL: "  ")) as Any }
        ] {
            do {
                _ = try createProvider()
                Issue.record("Expected InvalidArgumentError")
            } catch let error as InvalidArgumentError {
                #expect(error.argument == "baseURL")
                #expect(error.message == "baseURL must be a non-empty string.")
            } catch {
                Issue.record("Expected InvalidArgumentError, got \(error)")
            }
        }
    }
}
