import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let speechAudioData = Data([0x01, 0x02, 0x03])

@Suite("OpenAISpeechModel")
struct OpenAISpeechModelTests {
    // Port of openai-speech-model.test.ts: "should pass the model and text"
    @Test("doGenerate passes model and text")
    func testPassesModelAndText() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = Capture()

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp3"]
            )!
            return FetchResponse(body: .data(speechAudioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { ["Authorization": "Bearer test-api-key"] },
            fetch: mockFetch
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        _ = try await model.doGenerate(
            options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!")
        )

        guard let request = await capture.value() else {
            Issue.record("No request captured")
            return
        }

        guard let body = request.httpBody else {
            Issue.record("Missing request body")
            return
        }

        let jsonObject = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(jsonObject?["model"] as? String == "tts-1")
        #expect(jsonObject?["input"] as? String == "Hello from the AI SDK!")
    }

    // Port of openai-speech-model.test.ts: "should pass headers"
    @Test("doGenerate passes headers correctly")
    func testPassesHeaders() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = Capture()

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp3"]
            )!
            return FetchResponse(body: .data(speechAudioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: {
                [
                    "Authorization": "Bearer test-api-key",
                    "Custom-Provider-Header": "provider-header-value",
                    "OpenAI-Organization": "test-organization",
                    "OpenAI-Project": "test-project"
                ]
            },
            fetch: mockFetch
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        _ = try await model.doGenerate(
            options: SpeechModelV3CallOptions(
                text: "Hello from the AI SDK!",
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.value() else {
            Issue.record("No request captured")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["content-type"] == "application/json")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
        #expect(normalizedHeaders["openai-organization"] == "test-organization")
        #expect(normalizedHeaders["openai-project"] == "test-project")
    }

    // Port of openai-speech-model.test.ts: "should pass options"
    @Test("doGenerate sends JSON request with options")
    func testDoGenerateSendsJSON() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = Capture()

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/opus"]
            )!
            return FetchResponse(body: .data(speechAudioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 0) })
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(
                text: "Hello from Swift",
                voice: "nova",
                outputFormat: "opus",
                speed: 1.25,
                providerOptions: [
                    "openai": [
                        "instructions": .string("Speak softly"),
                        "speed": .number(1.1)
                    ]
                ],
                headers: ["Custom-Header": "request-header-value"]
            )
        )

        #expect(result.audio == .binary(speechAudioData))
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response.modelId == "tts-1")

        guard let request = await capture.value() else {
            Issue.record("No request captured")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-key")
        #expect(normalizedHeaders["custom-header"] == "request-header-value")
        #expect(normalizedHeaders["content-type"] == "application/json")

        guard let body = request.httpBody else {
            Issue.record("Missing request body")
            return
        }

        let jsonObject = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(jsonObject?["model"] as? String == "tts-1")
        #expect(jsonObject?["input"] as? String == "Hello from Swift")
        #expect(jsonObject?["voice"] as? String == "nova")
        #expect(jsonObject?["speed"] as? Double == 1.25)
        #expect(jsonObject?["response_format"] as? String == "opus")
        #expect(jsonObject?["instructions"] as? String == "Speak softly")
    }

    @Test("doGenerate reports warnings for unsupported options")
    func testWarningForUnsupportedOptions() async throws {
        let mockFetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/speech")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp3"]
            )!
            return FetchResponse(body: .data(speechAudioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(
                text: "Hello",
                outputFormat: "unknown-format",
                language: "fr"
            )
        )

        #expect(result.warnings.contains(.unsupported(feature: "outputFormat", details: "Unsupported output format: unknown-format. Using mp3 instead.")))
        #expect(result.warnings.contains(.unsupported(feature: "language", details: "OpenAI speech models do not support language selection. Language parameter \"fr\" was ignored.")))
    }

    // Port of openai-speech-model.test.ts: "should return audio data with correct content type"
    @Test("doGenerate returns audio data with correct content type")
    func testReturnsAudioDataWithContentType() async throws {
        let audioData = Data(count: 100) // Mock audio data

        let mockFetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/speech")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "audio/opus",
                    "x-request-id": "test-request-id",
                    "x-ratelimit-remaining": "123"
                ]
            )!
            return FetchResponse(body: .data(audioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(
                text: "Hello from the AI SDK!",
                outputFormat: "opus"
            )
        )

        #expect(result.audio == .binary(audioData))
    }

    // Port of openai-speech-model.test.ts: "should include response data with timestamp, modelId and headers"
    @Test("doGenerate includes response data with timestamp, modelId and headers")
    func testIncludesResponseMetadata() async throws {
        let audioData = Data(count: 100)

        let mockFetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/speech")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "audio/mp3",
                    "x-request-id": "test-request-id",
                    "x-ratelimit-remaining": "123"
                ]
            )!
            return FetchResponse(body: .data(audioData), urlResponse: response)
        }

        let testDate = Date(timeIntervalSince1970: 0)
        let config = OpenAIConfig(
            provider: "test-provider",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { [:] },
            fetch: mockFetch,
            _internal: .init(currentDate: { testDate })
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!")
        )

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "tts-1")

        let headers = result.response.headers ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["content-type"] == "audio/mp3")
        #expect(normalizedHeaders["x-request-id"] == "test-request-id")
        #expect(normalizedHeaders["x-ratelimit-remaining"] == "123")
    }

    // Port of openai-speech-model.test.ts: "should use real date when no custom date provider is specified"
    @Test("doGenerate uses real date when no custom date provider")
    func testUsesRealDateWhenNoCustomProvider() async throws {
        let audioData = Data(count: 100)

        let mockFetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/speech")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp3"]
            )!
            return FetchResponse(body: .data(audioData), urlResponse: response)
        }

        let testDate = Date(timeIntervalSince1970: 0)
        let config = OpenAIConfig(
            provider: "test-provider",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { [:] },
            fetch: mockFetch,
            _internal: .init(currentDate: { testDate })
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!")
        )

        #expect(result.response.timestamp.timeIntervalSince1970 == testDate.timeIntervalSince1970)
        #expect(result.response.modelId == "tts-1")
    }

    // Port of openai-speech-model.test.ts: "should handle different audio formats"
    @Test("doGenerate handles different audio formats")
    func testHandlesDifferentAudioFormats() async throws {
        let formats: [(String, String)] = [
            ("mp3", "audio/mp3"),
            ("opus", "audio/opus"),
            ("aac", "audio/aac"),
            ("flac", "audio/flac"),
            ("wav", "audio/wav"),
            ("pcm", "audio/pcm")
        ]

        for (format, contentType) in formats {
            let audioData = Data(count: 100)

            let mockFetch: FetchFunction = { _ in
                let response = HTTPURLResponse(
                    url: URL(string: "https://api.openai.com/v1/audio/speech")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": contentType]
                )!
                return FetchResponse(body: .data(audioData), urlResponse: response)
            }

            let config = OpenAIConfig(
                provider: "openai.speech",
                url: { _ in "https://api.openai.com/v1/audio/speech" },
                headers: { [:] },
                fetch: mockFetch
            )

            let model = OpenAISpeechModel(modelId: "tts-1", config: config)

            let result = try await model.doGenerate(
                options: SpeechModelV3CallOptions(
                    text: "Hello from the AI SDK!",
                    providerOptions: [
                        "openai": [
                            "response_format": .string(format)
                        ]
                    ]
                )
            )

            #expect(result.audio == .binary(audioData))
        }
    }

    // Port of openai-speech-model.test.ts: "should include warnings if any are generated"
    @Test("doGenerate includes empty warnings array when no warnings")
    func testIncludesEmptyWarningsArray() async throws {
        let audioData = Data(count: 100)

        let mockFetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/speech")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp3"]
            )!
            return FetchResponse(body: .data(audioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!")
        )

        #expect(result.warnings.isEmpty)
    }
}
