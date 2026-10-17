import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

private final class BatchAbort: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}

private actor TranscriptionRequests {
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
    func all() -> [URLRequest] { requests }
}

private let batchResponse = #"{"durationMilliseconds":2000.5,"combinedPhrases":[{"text":"Hello world."},{"text":"Next."}],"phrases":[{"text":"Hello world.","offsetMilliseconds":40.5,"durationMilliseconds":1500.25,"locale":"en-US","speaker":1,"confidence":0.9,"words":[{"text":"Hello","offsetMilliseconds":null,"durationMilliseconds":400}],"future":"drop"},{"text":"Next.","durationMilliseconds":null,"locale":"en-GB","speaker":null,"words":null}],"future":true}"#

private func transcriptionResponse(_ request: URLRequest, body: String = batchResponse, status: Int = 200) -> FetchResponse {
    FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status,
        httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Request-Id": "batch-request"])!)
}

private func batchDefinition(_ request: URLRequest) throws -> JSONObject {
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    let start = try #require(body.range(of: "name=\"definition\"\r\n\r\n")).upperBound
    let end = try #require(body.range(of: "\r\n", range: start..<body.endIndex)).lowerBound
    return try JSONDecoder().decode(JSONObject.self, from: Data(body[start..<end].utf8))
}

@Suite("Azure batch transcription")
struct AzureTranscriptionTests {
    @Test("Speech transcription sends its definition and returns timed text with lossless metadata")
    func generation() async throws {
        let requests = TranscriptionRequests()
        let provider = try createAzure(settings: .init(resourceName: "transcribe-resource", apiKey: "transcribe-key",
            fetch: { request in
                await requests.append(request)
                return transcriptionResponse(request, body: request.url?.path.contains("/audio/transcriptions") == true ? #"{"text":"OpenAI"}"# : batchResponse)
            }))
        let result = try await provider.transcription("mAi-TrAnScRiBe-2").doGenerate(options: .init(
            audio: .base64("AQID"), mediaType: "audio/wav", providerOptions: ["azure": [
                "timestamps": "word", "transcribeStyle": "clean", "locales": ["en"],
                "diarization": ["enabled": false], "phraseList": ["phrases": ["Vercel"]]
            ]]))
        let request = try #require(await requests.all().first)
        #expect(request.url?.absoluteString == "https://transcribe-resource.cognitiveservices.azure.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "transcribe-key")
        #expect(request.value(forHTTPHeaderField: "api-key") == nil)
        let form = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(form.contains("name=\"audio\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n\u{1}\u{2}\u{3}\r\n"))
        let definition = try batchDefinition(request)
        #expect(definition == ["enhancedMode": ["enabled": true, "model": "MAI-Transcribe-2",
            "modelOptions": ["timestamps": "word", "transcribeStyle": "clean"]], "locales": ["en"],
            "diarization": ["enabled": false], "phraseList": ["phrases": ["Vercel"]]])
        #expect(result.text == "Hello world. Next.")
        #expect(result.segments == [.init(text: "Hello world.", startSecond: 0.0405, endSecond: 1.54075)])
        #expect(result.language == "en")
        #expect(result.durationInSeconds == 2.0005)
        #expect(result.warnings == [])
        #expect(result.providerMetadata?["azure"]?["phrases"] == [
            ["text": "Hello world.", "offsetMilliseconds": 40.5, "durationMilliseconds": 1500.25,
             "locale": "en-US", "speaker": 1, "confidence": 0.9,
             "words": [["text": "Hello", "offsetMilliseconds": .null, "durationMilliseconds": 400]]],
            ["text": "Next.", "durationMilliseconds": .null, "locale": "en-GB", "speaker": .null, "words": .null]
        ])
        #expect(result.response.headers?["x-request-id"] == "batch-request")
        #expect(result.response.modelId == "mAi-TrAnScRiBe-2")
    }

    @Test("Known batch families select canonical names and their timestamp defaults", arguments: [
        ("MaI-TrAnScRiBe-1.5", "MAI-Transcribe-1.5", nil), ("MAI-Transcribe-2", "MAI-Transcribe-2", "segment"),
        ("mai-transcribe-2-custom", nil, nil)
    ] as [(String, String?, String?)])
    func defaults(_ id: String, _ expectedModel: String?, _ timestamps: String?) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            if let expectedModel {
                let definition = try batchDefinition(request)
                #expect(definition == ["enhancedMode": ["enabled": true, "model": .string(expectedModel),
                    "modelOptions": .object(timestamps.map { ["timestamps": .string($0)] } ?? [:])]])
                return transcriptionResponse(request, body: #"{"combinedPhrases":[],"phrases":null,"durationMilliseconds":null}"#)
            }
            #expect(request.url?.path == "/openai/v1/audio/transcriptions")
            return transcriptionResponse(request, body: #"{"text":"OpenAI"}"#)
        }))
        let api: any ProviderV4 = provider
        let model = try #require(try api.transcriptionModel(modelId: id))
        let result = try await model.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        #expect(result.text == (expectedModel == nil ? "OpenAI" : ""))
        #expect(result.segments == [])
        #expect(result.language == nil)
        #expect(result.durationInSeconds == nil)
        if expectedModel != nil { #expect(result.providerMetadata?["azure"]?["phrases"] == []) }
    }

    @Test("A batch model selects its API per request and preserves explicit unsupported options")
    func selection() async throws {
        let requests = TranscriptionRequests()
        let provider = try createAzure(settings: .init(baseURL: "https://gateway.example.com/openai/", speechBaseURL: "https://speech.example.com/",
            tokenProvider: { "batch-token" }, headers: ["X-Config": "configured"], fetch: { request in
                await requests.append(request)
                if request.url?.path == "/openai/audio/transcriptions" { return transcriptionResponse(request, body: #"{"text":"OpenAI"}"#) }
                let definition = try batchDefinition(request)
                #expect(definition["enhancedMode"] == ["enabled": true, "model": "MAI-Transcribe-1.5", "modelOptions": ["timestamps": "word"]])
                #expect(request.value(forHTTPHeaderField: "X-Config") == "caller")
                return transcriptionResponse(request, body: #"{"combinedPhrases":[{"text":"Speech"}]}"#)
            }))
        let model = provider.transcriptionModel("mai-transcribe-1.5")
        let settings = AzureTranscriptionModelOptions(api: .speech, timestamps: .word, language: "en")
        let raw = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(settings))
        let first = try await model.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["azure": raw], headers: ["X-Config": "caller"]))
        let second = try await model.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav",
            providerOptions: ["azure": ["api": "openai", "timestamps": "none", "language": "en"], "openai": ["language": "de", "prompt": "Names"]],
            headers: ["Authorization": "Bearer caller"]))
        let all = await requests.all()
        #expect(all.map { $0.url?.absoluteString } == [
            "https://speech.example.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15",
            "https://gateway.example.com/openai/audio/transcriptions"])
        #expect(all.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer batch-token", "Bearer caller"])
        let form = String(decoding: try #require(all[1].httpBody), as: UTF8.self)
        #expect(form.contains("name=\"language\"\r\n\r\nde\r\n"))
        #expect(form.contains("name=\"prompt\"\r\n\r\nNames\r\n"))
        #expect(first.text == "Speech")
        #expect(first.warnings == [.unsupported(feature: "providerOptions.azure.language", details: "This option requires MAI streaming transcription.")])
        #expect(second.text == "OpenAI")
        #expect(second.warnings == [
            .unsupported(feature: "providerOptions.azure.timestamps", details: "This option requires the Azure Speech API."),
            .unsupported(feature: "providerOptions.azure.language", details: "This option requires MAI streaming transcription.")
        ])
    }

    @Test("All reported locales participate in language classification", arguments: [
        (["en-US", "en-GB"], "en"), (["en-US", "de-DE"], nil), (["fil"], nil), (["en", "fil"], nil)
    ] as [([String], String?)])
    func languages(_ locales: [String], _ expected: String?) async throws {
        let body: JSONValue = ["combinedPhrases": [["text": "text"]], "phrases": .array(locales.map { ["text": "text", "locale": .string($0)] })]
        let encoded = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { transcriptionResponse($0, body: encoded) }))
        let result = try await provider.transcription("mai-transcribe-2").doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
        #expect(result.language == expected)
        #expect(result.segments == [])
    }

    @Test("Strict transcription options reject unsupported or malformed shapes", arguments: [
        ["api": JSONValue.string("invalid")], ["language": .string("")], ["language": .null],
        ["timestamps": .string("invalid")], ["locales": .array([])], ["locales": ["en", "de"]],
        ["diarization": ["enabled": true, "maxSpeakers": 2]], ["diarization": ["enabled": "yes"]],
        ["phraseList": ["phrases": ["term"], "biasingWeight": 1.5]], ["timestamp": "word"]
    ])
    func options(_ fields: JSONObject) async throws {
        let provider = try createAzure(settings: .init(fetch: { _ in throw URLError(.cannotConnectToHost) }))
        let error = await #expect(throws: InvalidArgumentError.self) {
            try await provider.transcription("mai-transcribe-2").doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["azure": fields]))
        }
        #expect(error?.argument == "providerOptions")
    }

    @Test("Streaming and file-only branches fail with their actual unsupported capability")
    func unsupported() async throws {
        let provider = try createAzure()
        let file = await #expect(throws: UnsupportedFunctionalityError.self) {
            try await provider.transcription("MAI-Transcribe-2-Streaming").doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
        }
        #expect(file?.functionality == "file transcription with MAI-Transcribe-2-Streaming (use streaming transcription)")
        let stream = await #expect(throws: UnsupportedFunctionalityError.self) {
            try await provider.transcription("mai-transcribe-2").doStream(options: .init(audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm")))
        }
        #expect(stream?.functionality == "streaming transcription with the Azure Speech API")
    }

    @Test("Batch abort releases a retained response body before returning")
    func cancellation() async throws {
        let aborted = BatchAbort()
        let released = BatchAbort()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        source.continuation.onTermination = { reason in if case .cancelled = reason { released.set() } }
        defer { source.continuation.finish() }
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            aborted.set()
            return FetchResponse(body: .stream(source.stream), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }))
        let timedOut = BatchAbort()
        let operation = Task {
            try await provider.transcription("mai-transcribe-2").doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", abortSignal: { aborted.value }))
        }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            timedOut.set()
            operation.cancel()
        }
        defer { watchdog.cancel(); operation.cancel() }
        _ = await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(!timedOut.value)
        #expect(released.value)
        withExtendedLifetime(source) {}
    }

    @Test("Speech transcription errors retain both documented envelopes and raw diagnostics", arguments: [
        (400, #"{"error":{"message":"Bad audio","code":"Invalid"}}"#, "Bad audio"),
        (429, #"{"code":"Limit","message":"Try later"}"#, "Try later"),
        (503, "Unavailable", nil), (200, #"{"unrelated":true}"#, "Invalid JSON response")
    ] as [(Int, String, String?)])
    func errors(_ status: Int, _ body: String, _ message: String?) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { transcriptionResponse($0, body: body, status: status) }))
        let error = await #expect(throws: APICallError.self) {
            try await provider.transcription("mai-transcribe-2").doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        }
        #expect(error?.statusCode == status)
        #expect(error?.responseBody == body)
        #expect(error?.responseHeaders?["x-request-id"] == "batch-request")
        if let message { #expect(error?.message == message) }
        if status != 200 { #expect(error?.isRetryable == (status != 400)) }
        let values = try #require(error?.requestBodyValues as? [String: FormDataValue])
        #expect(values["audio"] == .data(Data([1]), filename: "audio.wav", contentType: "audio/wav"))
    }
}
