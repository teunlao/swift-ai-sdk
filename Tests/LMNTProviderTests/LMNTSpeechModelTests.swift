import Foundation
import Testing
@testable import LMNTProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils

private let provider = createLMNT(settings: LMNTProviderSettings(apiKey: "test-api-key"))
private let model = provider.speech(.aurora)

@Suite("LMNTSpeechModel")
struct LMNTSpeechModelTests {
    private func mockBinaryResponse(format: String = "mp3", headers: [String: String] = [:]) -> (FetchFunction, Data) {
        let audio = Data(Array(repeating: 0, count: 100))
        let fetch: FetchFunction = { request in
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/\(format)"] .merging(headers, uniquingKeysWith: { $1 })
            )!
            return FetchResponse(body: .data(audio), urlResponse: resp)
        }
        return (fetch, audio)
    }

    @Test("should pass the model and text")
    func passModelAndText() async throws {
        actor Capture { var request: URLRequest?; func store(_ r: URLRequest) { request = r }; func value() -> URLRequest? { request } }
        let cap = Capture()
        let (fetch, _) = mockBinaryResponse()

        let provider = createLMNT(settings: LMNTProviderSettings(apiKey: "test", fetch: { req in await cap.store(req); return try await fetch(req) }))
        _ = try await provider.speech(.aurora).doGenerate(options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!"))

        guard let request = await cap.value(), let body = request.httpBody else { Issue.record("Expected captured request body"); return }
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(json["model"] as? String == "aurora")
        #expect(json["text"] as? String == "Hello from the AI SDK!")
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        actor Capture { var request: URLRequest?; func store(_ r: URLRequest) { request = r }; func value() -> URLRequest? { request } }
        let cap = Capture()
        let (fetch, _) = mockBinaryResponse()

        let provider = createLMNT(settings: LMNTProviderSettings(
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: { req in await cap.store(req); return try await fetch(req) }
        ))

        _ = try await provider.speech(.aurora).doGenerate(options: SpeechModelV3CallOptions(
            text: "Hello from the AI SDK!",
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let req = await cap.value() else { Issue.record("No request"); return }
        let headers = (req.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { r, p in r[p.key.lowercased()] = p.value }
        #expect(headers["x-api-key"] == "test-api-key")
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
    }

    @Test("should pass options")
    func passOptions() async throws {
        actor Capture { var request: URLRequest?; func store(_ r: URLRequest) { request = r }; func value() -> URLRequest? { request } }
        let cap = Capture()
        let (fetch, _) = mockBinaryResponse()

        let provider = createLMNT(settings: LMNTProviderSettings(apiKey: "test", fetch: { req in await cap.store(req); return try await fetch(req) }))
        _ = try await provider.speech(.aurora).doGenerate(options: SpeechModelV3CallOptions(
            text: "Hello from the AI SDK!",
            voice: "nova",
            outputFormat: "mp3",
            speed: 1.5
        ))

        guard let req = await cap.value(), let data = req.httpBody else { Issue.record("No body"); return }
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["model"] as? String == "aurora")
        #expect(json["text"] as? String == "Hello from the AI SDK!")
        #expect(json["voice"] as? String == "nova")
        #expect(json["speed"] as? Double == 1.5)
        #expect(json["response_format"] as? String == "mp3")
    }

    @Test("should return audio data with correct content type")
    func returnAudioData() async throws {
        let (fetch, audio) = mockBinaryResponse(format: "mp3", headers: ["x-request-id": "test-request-id", "x-ratelimit-remaining": "123"])
        let provider = createLMNT(settings: LMNTProviderSettings(apiKey: "test", fetch: fetch))
        let result = try await provider.speech(.aurora).doGenerate(options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!", outputFormat: "mp3"))
        if case let .binary(data) = result.audio {
            #expect(data == audio)
        } else { Issue.record("Expected binary audio") }
    }

    @Test("should include response data with timestamp, modelId and headers")
    func includeResponseData() async throws {
        let (fetchImpl, _) = mockBinaryResponse(headers: ["x-request-id": "test-request-id", "x-ratelimit-remaining": "123"]) 
        let testDate = Date(timeIntervalSince1970: 0)
        let model = LMNTSpeechModel(.aurora, config: LMNTConfig(
            provider: "test-provider",
            url: { _ in "https://api.lmnt.com/v1/ai/speech/bytes" },
            headers: { [:] },
            fetch: fetchImpl,
            currentDate: { testDate }
        ))
        let result = try await model.doGenerate(options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!"))
        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "aurora")
        let headers = result.response.headers ?? [:]
        #expect(headers["content-type"] == "audio/mp3")
        #expect(headers["x-request-id"] == "test-request-id")
        #expect(headers["x-ratelimit-remaining"] == "123")
    }

    @Test("should use real date when no custom date provider is specified")
    func useRealDateWhenNoCustomProvider() async throws {
        let (fetchImpl, _) = mockBinaryResponse()
        let testDate = Date(timeIntervalSince1970: 0)
        let model = LMNTSpeechModel(.aurora, config: LMNTConfig(
            provider: "test-provider",
            url: { _ in "https://api.lmnt.com/v1/ai/speech/bytes" },
            headers: { [:] },
            fetch: fetchImpl,
            currentDate: { testDate }
        ))
        let result = try await model.doGenerate(options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!"))
        #expect(result.response.timestamp.timeIntervalSince1970 == testDate.timeIntervalSince1970)
        #expect(result.response.modelId == "aurora")
    }

    @Test("should handle different audio formats")
    func handleDifferentFormats() async throws {
        for format in ["aac", "mp3", "mulaw", "raw", "wav"] {
            let (fetch, audio) = mockBinaryResponse(format: format)
            let provider = createLMNT(settings: LMNTProviderSettings(apiKey: "test", fetch: fetch))
            let result = try await provider.speech(.aurora).doGenerate(options: SpeechModelV3CallOptions(
                text: "Hello from the AI SDK!",
                providerOptions: ["lmnt": ["format": .string(format)]]
            ))
            if case let .binary(data) = result.audio { #expect(data == audio) } else { Issue.record("Expected binary") }
        }
    }

    @Test("should include warnings if any are generated")
    func includeWarnings() async throws {
        let (fetch, _) = mockBinaryResponse()
        let provider = createLMNT(settings: LMNTProviderSettings(apiKey: "test", fetch: fetch))
        let result = try await provider.speech(.aurora).doGenerate(options: SpeechModelV3CallOptions(text: "Hello from the AI SDK!"))
        #expect(result.warnings.isEmpty)
    }
}

