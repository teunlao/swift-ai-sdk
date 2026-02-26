import Foundation
import Testing
@testable import DeepgramProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("DeepgramSpeechModel")
struct DeepgramSpeechModelTests {
    actor Capture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func request(at index: Int) -> URLRequest? { requests.indices.contains(index) ? requests[index] : nil }
        func last() -> URLRequest? { requests.last }
    }

    private func mockBinaryResponse(headers: [String: String] = [:]) -> (FetchFunction, Data) {
        let audio = Data(Array(repeating: 0, count: 100))
        let fetch: FetchFunction = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp3"].merging(headers, uniquingKeysWith: { $1 })
            )!
            return FetchResponse(body: .data(audio), urlResponse: response)
        }
        return (fetch, audio)
    }

    private func queryValue(_ request: URLRequest, name: String) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            return nil
        }
        return items.first(where: { $0.name == name })?.value
    }

    private func headersLowercased(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    @Test("should pass the model and text")
    func passModelAndText() async throws {
        let capture = Capture()
        let (fetchImpl, _) = mockBinaryResponse()

        let provider = createDeepgram(settings: DeepgramProviderSettings(
            apiKey: "test-api-key",
            fetch: { request in await capture.append(request); return try await fetchImpl(request) }
        ))

        _ = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(text: "Hello, welcome to Deepgram!")
        )

        guard let request = await capture.last(),
              let body = request.httpBody else {
            Issue.record("Expected captured request body")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["text"] as? String == "Hello, welcome to Deepgram!")
        #expect(queryValue(request, name: "model") == "aura-2-helena-en")
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        let capture = Capture()
        let (fetchImpl, _) = mockBinaryResponse()

        let provider = createDeepgram(settings: DeepgramProviderSettings(
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: { request in await capture.append(request); return try await fetchImpl(request) }
        ))

        _ = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.last() else {
            Issue.record("Expected captured request")
            return
        }

        let headers = headersLowercased(request)
        #expect(headers["authorization"] == "Token test-api-key")
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["user-agent"]?.contains("ai-sdk/deepgram/\(DEEPGRAM_VERSION)") == true)
    }

    @Test("should map outputFormat to encoding/container")
    func mapOutputFormat() async throws {
        let capture = Capture()
        let (fetchImpl, _) = mockBinaryResponse()

        let provider = createDeepgram(settings: DeepgramProviderSettings(
            apiKey: "test-api-key",
            fetch: { request in await capture.append(request); return try await fetchImpl(request) }
        ))

        _ = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                outputFormat: "wav"
            )
        )

        guard let request = await capture.last() else {
            Issue.record("Expected captured request")
            return
        }

        #expect(queryValue(request, name: "container") == "wav")
        #expect(queryValue(request, name: "encoding") == "linear16")
    }

    @Test("should pass provider options")
    func passProviderOptions() async throws {
        let capture = Capture()
        let (fetchImpl, _) = mockBinaryResponse()

        let provider = createDeepgram(settings: DeepgramProviderSettings(
            apiKey: "test-api-key",
            fetch: { request in await capture.append(request); return try await fetchImpl(request) }
        ))

        _ = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                providerOptions: [
                    "deepgram": [
                        "encoding": .string("mp3"),
                        "bitRate": .number(48_000),
                        "container": .string("wav"),
                        "callback": .string("https://example.com/callback"),
                        "callbackMethod": .string("POST"),
                        "mipOptOut": .bool(true),
                        "tag": .string("test-tag")
                    ]
                ]
            )
        )

        guard let request = await capture.last() else {
            Issue.record("Expected captured request")
            return
        }

        #expect(queryValue(request, name: "encoding") == "mp3")
        #expect(queryValue(request, name: "bit_rate") == "48000")
        #expect(queryValue(request, name: "container") == nil)
        #expect(queryValue(request, name: "callback") == "https://example.com/callback")
        #expect(queryValue(request, name: "callback_method") == "POST")
        #expect(queryValue(request, name: "mip_opt_out") == "true")
        #expect(queryValue(request, name: "tag") == "test-tag")
    }

    @Test("should handle array tag")
    func handleArrayTag() async throws {
        let capture = Capture()
        let (fetchImpl, _) = mockBinaryResponse()

        let provider = createDeepgram(settings: DeepgramProviderSettings(
            apiKey: "test-api-key",
            fetch: { request in await capture.append(request); return try await fetchImpl(request) }
        ))

        _ = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                providerOptions: [
                    "deepgram": [
                        "tag": .array([.string("tag1"), .string("tag2")])
                    ]
                ]
            )
        )

        guard let request = await capture.last() else {
            Issue.record("Expected captured request")
            return
        }

        #expect(queryValue(request, name: "tag") == "tag1,tag2")
    }

    @Test("should return audio data")
    func returnAudioData() async throws {
        let (fetchImpl, audio) = mockBinaryResponse(headers: ["x-request-id": "test-request-id"])
        let provider = createDeepgram(settings: DeepgramProviderSettings(apiKey: "test-api-key", fetch: fetchImpl))
        let result = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(options: .init(text: "Hello, welcome to Deepgram!"))
        #expect(result.audio == .binary(audio))
    }

    @Test("should include response data with timestamp, modelId and headers")
    func includeResponseData() async throws {
        let audio = Data(Array(repeating: 0, count: 100))
        let fetch: FetchFunction = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "audio/mp3",
                    "x-request-id": "test-request-id"
                ]
            )!
            return FetchResponse(body: .data(audio), urlResponse: response)
        }

        let testDate = Date(timeIntervalSince1970: 0)
        let model = DeepgramSpeechModel(
            modelId: .aura2HelenaEn,
            config: DeepgramSpeechModel.Config(
                provider: "test-provider",
                url: { _ in "https://api.deepgram.com/v1/speak" },
                headers: { [:] },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: .init(text: "Hello, welcome to Deepgram!"))
        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "aura-2-helena-en")
        let headers = result.response.headers ?? [:]
        #expect(headers["content-type"] == "audio/mp3")
        #expect(headers["x-request-id"] == "test-request-id")
    }

    @Test("should warn about unsupported voice parameter")
    func warnVoice() async throws {
        let (fetchImpl, _) = mockBinaryResponse()
        let provider = createDeepgram(settings: DeepgramProviderSettings(apiKey: "test-api-key", fetch: fetchImpl))
        let result = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(text: "Hello, welcome to Deepgram!", voice: "different-voice")
        )
        #expect(result.warnings == [
            .unsupported(
                feature: "voice",
                details: "Deepgram TTS models embed the voice in the model ID. The voice parameter \"different-voice\" was ignored. Use the model ID to select a voice (e.g., \"aura-2-helena-en\")."
            )
        ])
    }

    @Test("should warn about unsupported speed parameter")
    func warnSpeed() async throws {
        let (fetchImpl, _) = mockBinaryResponse()
        let provider = createDeepgram(settings: DeepgramProviderSettings(apiKey: "test-api-key", fetch: fetchImpl))
        let result = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(text: "Hello, welcome to Deepgram!", speed: 1.5)
        )
        #expect(result.warnings == [
            .unsupported(
                feature: "speed",
                details: "Deepgram TTS REST API does not support speed adjustment. Speed parameter was ignored."
            )
        ])
    }

    @Test("should warn about unsupported language parameter")
    func warnLanguage() async throws {
        let (fetchImpl, _) = mockBinaryResponse()
        let provider = createDeepgram(settings: DeepgramProviderSettings(apiKey: "test-api-key", fetch: fetchImpl))
        let result = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(text: "Hello, welcome to Deepgram!", language: "en")
        )
        #expect(result.warnings == [
            .unsupported(
                feature: "language",
                details: "Deepgram TTS models are language-specific via the model ID. Language parameter \"en\" was ignored. Select a model with the appropriate language suffix (e.g., \"-en\" for English)."
            )
        ])
    }

    @Test("should warn about unsupported instructions parameter")
    func warnInstructions() async throws {
        let (fetchImpl, _) = mockBinaryResponse()
        let provider = createDeepgram(settings: DeepgramProviderSettings(apiKey: "test-api-key", fetch: fetchImpl))
        let result = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(
            options: .init(text: "Hello, welcome to Deepgram!", instructions: "Speak slowly")
        )
        #expect(result.warnings == [
            .unsupported(
                feature: "instructions",
                details: "Deepgram TTS REST API does not support instructions. Instructions parameter was ignored."
            )
        ])
    }

    @Test("should include request body in response")
    func includeRequestBody() async throws {
        let (fetchImpl, _) = mockBinaryResponse()
        let provider = createDeepgram(settings: DeepgramProviderSettings(apiKey: "test-api-key", fetch: fetchImpl))
        let result = try await provider.speech(modelId: .aura2HelenaEn).doGenerate(options: .init(text: "Hello, welcome to Deepgram!"))
        #expect(result.request?.body as? String == "{\"text\":\"Hello, welcome to Deepgram!\"}")
    }

    @Test("should clean up incompatible parameters when encoding changes via providerOptions")
    func cleanUpWhenEncodingChanges() async throws {
        let capture = Capture()
        let (fetchImpl, _) = mockBinaryResponse()

        let provider = createDeepgram(settings: DeepgramProviderSettings(
            apiKey: "test-api-key",
            fetch: { request in await capture.append(request); return try await fetchImpl(request) }
        ))

        let model = provider.speech(modelId: .aura2HelenaEn)

        _ = try await model.doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                outputFormat: "linear16_16000",
                providerOptions: [
                    "deepgram": ["encoding": .string("mp3")]
                ]
            )
        )

        _ = try await model.doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                outputFormat: "linear16_16000",
                providerOptions: [
                    "deepgram": ["encoding": .string("opus")]
                ]
            )
        )

        _ = try await model.doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                outputFormat: "mp3",
                providerOptions: [
                    "deepgram": [
                        "encoding": .string("linear16"),
                        "bitRate": .number(48_000)
                    ]
                ]
            )
        )

        guard let r1 = await capture.request(at: 0),
              let r2 = await capture.request(at: 1),
              let r3 = await capture.request(at: 2) else {
            Issue.record("Expected 3 captured requests")
            return
        }

        #expect(queryValue(r1, name: "encoding") == "mp3")
        #expect(queryValue(r1, name: "sample_rate") == nil)

        #expect(queryValue(r2, name: "encoding") == "opus")
        #expect(queryValue(r2, name: "container") == "ogg")
        #expect(queryValue(r2, name: "sample_rate") == nil)

        #expect(queryValue(r3, name: "encoding") == "linear16")
        #expect(queryValue(r3, name: "bit_rate") == nil)
    }

    @Test("should clean up incompatible parameters when container changes encoding implicitly")
    func cleanUpWhenContainerChangesEncoding() async throws {
        let capture = Capture()
        let (fetchImpl, _) = mockBinaryResponse()

        let provider = createDeepgram(settings: DeepgramProviderSettings(
            apiKey: "test-api-key",
            fetch: { request in await capture.append(request); return try await fetchImpl(request) }
        ))

        let model = provider.speech(modelId: .aura2HelenaEn)

        _ = try await model.doGenerate(
            options: .init(
                text: "Hello, welcome to Deepgram!",
                outputFormat: "linear16_16000",
                providerOptions: [
                    "deepgram": ["container": .string("ogg")]
                ]
            )
        )

        guard let request = await capture.last() else {
            Issue.record("Expected captured request")
            return
        }

        #expect(queryValue(request, name: "encoding") == "opus")
        #expect(queryValue(request, name: "container") == "ogg")
        #expect(queryValue(request, name: "sample_rate") == nil)
    }
}

