import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

private let speechAudio = Data([0x00, 0xFF, 0x0D, 0x0A])

private actor SpeechRequests {
    private var request: URLRequest?
    func store(_ request: URLRequest) { self.request = request }
    func first() -> URLRequest? { request }
}

private final class SpeechFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private func speechResponse(_ request: URLRequest, body: ProviderHTTPResponseBody = .data(speechAudio), status: Int = 200) -> FetchResponse {
    FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "audio/mpeg", "X-Request-Id": "speech-request"])!)
}

@Suite("OpenAISpeechModel")
struct OpenAISpeechModelTests {
    @Test("provider options override portable values while audio and request metadata stay intact", arguments: [0.25, 4.0])
    func generation(_ speed: Double) async throws {
        let requests = SpeechRequests()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "speech-key", organization: "speech-org", project: "speech-project",
            headers: ["X-Speech": "configured"], fetch: { request in
                await requests.store(request)
                return speechResponse(request)
            }
        ))
        let before = Date()
        let result = try await provider.speech("gpt-4o-mini-tts-2025-12-15").doGenerate(options: .init(
            text: "Hello / speech", voice: "nova", outputFormat: "opus", instructions: "portable", speed: 1.5,
            providerOptions: ["openai": ["speed": .number(speed), "instructions": ""]], headers: ["X-Speech": "caller"]
        ))
        let request = try #require(await requests.first())
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body == .object(["model": "gpt-4o-mini-tts-2025-12-15", "input": "Hello / speech",
            "voice": "nova", "response_format": "opus", "speed": .number(speed), "instructions": ""]))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer speech-key")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == "speech-org")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == "speech-project")
        #expect(request.value(forHTTPHeaderField: "X-Speech") == "caller")
        #expect(result.audio == .binary(speechAudio))
        #expect(result.warnings == [])
        #expect(result.response.modelId == "gpt-4o-mini-tts-2025-12-15")
        #expect(result.response.timestamp >= before && result.response.timestamp <= Date())
        #expect(result.response.headers?["content-type"] == "audio/mpeg")
        #expect(result.response.headers?["x-request-id"] == "speech-request")
        let recorded = try #require(result.request?.body as? String)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(recorded.utf8)) == body)
    }

    @Test("nullish and partial provider options preserve portable fields", arguments: [
        (["speed": JSONValue.null, "instructions": .null], "portable"),
        (["instructions": JSONValue.string("provider")], "provider")
    ])
    func partialOptions(_ options: JSONObject, _ instructions: String) async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object(["model": "tts-1", "input": "hello", "voice": "alloy",
                "response_format": "mp3", "speed": 1.5, "instructions": .string(instructions)]))
            return speechResponse(request)
        })).speech("tts-1")
        let result = try await model.doGenerate(options: .init(text: "hello", instructions: "portable", speed: 1.5,
            providerOptions: ["openai": options]))
        #expect(result.audio == .binary(speechAudio))
    }

    @Test("empty portable strings preserve voice and use silent mp3 fallback")
    func emptyOptions() async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object(["model": "custom-tts", "input": "", "voice": "", "response_format": "mp3"]))
            return speechResponse(request)
        })).speech("custom-tts")
        let result = try await model.doGenerate(options: .init(text: "", voice: "", outputFormat: "", language: "",
            providerOptions: ["openai": ["voice": "nova", "response_format": "wav"]]))
        #expect(result.warnings == [])
        #expect(result.audio == .binary(speechAudio))
    }

    @Test("portable output formats reach the API", arguments: ["mp3", "opus", "aac", "flac", "wav", "pcm"])
    func formats(_ format: String) async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode([String: JSONValue].self, from: #require(request.httpBody))
            #expect(body["response_format"] == .string(format))
            return speechResponse(request)
        })).speech("tts-1")
        let result = try await model.doGenerate(options: .init(text: "hello", outputFormat: format))
        #expect(result.audio == .binary(speechAudio))
        #expect(result.warnings == [])
    }

    @Test("unsupported output and language produce ordered warnings with mp3 fallback")
    func warnings() async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object(["model": "tts-1", "input": "hello", "voice": "alloy", "response_format": "mp3"]))
            return speechResponse(request)
        })).speech("tts-1")
        let result = try await model.doGenerate(options: .init(text: "hello", outputFormat: "invalid", language: "fr"))
        #expect(result.warnings == [
            .unsupported(feature: "outputFormat", details: "Unsupported output format: invalid. Using mp3 instead."),
            .unsupported(feature: "language", details: "OpenAI speech models do not support language selection. Language parameter \"fr\" was ignored.")
        ])
    }

    @Test("provider option validation rejects invalid ratios and instructions before HTTP", arguments: [
        ["speed": JSONValue.number(0.24)], ["speed": .number(4.1)], ["speed": .number(.nan)],
        ["speed": .number(.infinity)], ["instructions": .number(17)]
    ])
    func invalidOptions(_ options: JSONObject) async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { _ in
            Issue.record("Invalid provider options must not reach HTTP")
            throw CancellationError()
        })).speech("tts-1")
        let error = await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(text: "hello", providerOptions: ["openai": options]))
        }
        #expect(error?.argument == "providerOptions")
    }

    @Test("buffered audio joins every chunk and preserves an injected timestamp")
    func bufferedAudio() async throws {
        let model = OpenAISpeechModel(modelId: "tts-1-hd-1106", config: .init(
            provider: "custom.speech", url: { "https://example.com\($0.path)" }, fetch: { request in
                let stream = AsyncThrowingStream<Data, Error> { continuation in
                    continuation.yield(Data([0x00, 0xFF]))
                    continuation.yield(Data([0x0D, 0x0A]))
                    continuation.finish()
                }
                return speechResponse(request, body: .stream(stream))
            }, _internal: .init(currentDate: { Date(timeIntervalSince1970: 42) })
        ))
        let result = try await model.doGenerate(options: .init(text: "hello"))
        #expect(result.audio == .binary(speechAudio))
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 42))
        #expect(result.response.modelId == "tts-1-hd-1106")
    }

    @Test("API failure retains provider message and request diagnostics")
    func apiError() async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: {
            speechResponse($0, body: .data(Data(#"{"error":{"message":"speech denied","type":"invalid_request_error"}}"#.utf8)), status: 403)
        })).speech("tts-1")
        let error = await #expect(throws: APICallError.self) { try await model.doGenerate(options: .init(text: "hello")) }
        #expect(error?.statusCode == 403)
        #expect(error?.message == "speech denied")
        #expect(error?.requestBodyValues as? JSONValue == .object(["model": "tts-1", "input": "hello", "voice": "alloy", "response_format": "mp3"]))
    }

    @Test("a missing binary body remains a typed API failure")
    func emptyResponse() async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { speechResponse($0, body: .none) })).speech("tts-1")
        let error = await #expect(throws: APICallError.self) { try await model.doGenerate(options: .init(text: "hello")) }
        #expect(error?.statusCode == 200)
        #expect(error?.message == "Response body is empty")
    }

    @Test("abort at body handoff cancels a retained audio source before returning")
    func abortBody() async throws {
        let aborted = SpeechFlag()
        let cancelled = SpeechFlag()
        let timedOut = SpeechFlag()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        source.continuation.onTermination = { reason in if case .cancelled = reason { cancelled.set() } }
        defer { source.continuation.finish() }
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            aborted.set()
            return speechResponse(request, body: .stream(source.stream))
        })).speech("tts-1")
        let operation = Task { try await model.doGenerate(options: .init(text: "hello", abortSignal: { aborted.value })) }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            timedOut.set()
            operation.cancel()
        }
        defer { watchdog.cancel(); operation.cancel() }
        _ = await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(!timedOut.value)
        #expect(cancelled.value)
        withExtendedLifetime(source) {}
    }
}
