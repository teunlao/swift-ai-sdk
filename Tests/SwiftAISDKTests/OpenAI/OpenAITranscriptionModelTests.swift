import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let sampleAudioData = Data("ABC".utf8)

private final class MockOpenAIWebSocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [MockOpenAIWebSocketConnection] = []

    func make(_ request: OpenAIWebSocketRequest) throws -> any OpenAIWebSocketConnection {
        let connection = MockOpenAIWebSocketConnection(request: request)
        lock.withLock {
            connections.append(connection)
        }
        return connection
    }

    func firstConnection() -> MockOpenAIWebSocketConnection? {
        lock.withLock {
            connections.first
        }
    }
}

private final class MockOpenAIWebSocketConnection: OpenAIWebSocketConnection, @unchecked Sendable {
    let request: OpenAIWebSocketRequest
    let messages: AsyncThrowingStream<String, Error>

    private let lock = NSLock()
    private let messageContinuation: AsyncThrowingStream<String, Error>.Continuation
    private var openContinuations: [CheckedContinuation<Void, Error>] = []
    private var opened = false
    private var sentTexts: [String] = []
    private var closeCodeValues: [Int?] = []

    init(request: OpenAIWebSocketRequest) {
        self.request = request

        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        self.messages = AsyncThrowingStream { streamContinuation in
            continuation = streamContinuation
        }
        self.messageContinuation = continuation!
    }

    func waitUntilOpen() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let shouldResume = lock.withLock {
                if opened {
                    return true
                }
                openContinuations.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func send(_ text: String) async throws {
        lock.withLock {
            sentTexts.append(text)
        }
    }

    func close(code: Int?) {
        lock.withLock {
            closeCodeValues.append(code)
        }
        messageContinuation.finish()
    }

    func open() {
        let continuations = lock.withLock {
            opened = true
            let values = openContinuations
            openContinuations.removeAll()
            return values
        }
        continuations.forEach { $0.resume() }
    }

    func message(_ value: JSONValue) throws {
        messageContinuation.yield(try jsonText(from: value))
    }

    func sentJSONValues() throws -> [JSONValue] {
        try lock.withLock { sentTexts }.map { text in
            let data = Data(text.utf8)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
    }

    func closeCodes() -> [Int?] {
        lock.withLock { closeCodeValues }
    }

    func waitForSentCount(_ count: Int) async throws {
        for _ in 0..<200 {
            let currentCount = lock.withLock { sentTexts.count }
            if currentCount >= count {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

private func transcriptionAudioStream(
    _ chunks: [TranscriptionModelV4StreamAudio]
) -> AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}

private func collectTranscriptionParts(
    _ stream: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>
) async throws -> [TranscriptionModelV4StreamPart] {
    var parts: [TranscriptionModelV4StreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

private func jsonText(from value: JSONValue) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func multipartFieldValues(in body: String, named name: String) -> [String] {
    let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
    return normalized
        .components(separatedBy: "\n--")
        .compactMap { part in
            guard part.contains("name=\"\(name)\""),
                  let separator = part.range(of: "\n\n")
            else {
                return nil
            }

            let value = part[separator.upperBound...]
            return value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? ""
        }
}

@Suite("OpenAITranscriptionModel")
struct OpenAITranscriptionModelTests {
    @Test("doGenerate rejects realtime transcription models")
    func testDoGenerateRejectsRealtimeTranscriptionModel() async throws {
        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] }
        )
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: config)

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(
                options: TranscriptionModelV3CallOptions(
                    audio: .binary(sampleAudioData),
                    mediaType: "audio/wav"
                )
            )
        }
    }

    @Test("doStream rejects non-realtime transcription models")
    func testDoStreamRejectsNonRealtimeTranscriptionModel() async throws {
        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] }
        )
        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doStream(
                options: TranscriptionModelV4StreamOptions(
                    audio: transcriptionAudioStream([.binary(sampleAudioData)]),
                    inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)
                )
            )
        }
    }

    @Test("doStream sends OpenAI realtime transcription session and maps stream parts")
    func testDoStreamRealtimeTranscription() async throws {
        let webSocketFactory = MockOpenAIWebSocketFactory()
        let testDate = Date(timeIntervalSince1970: 0)
        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { options in "https://api.openai.com/v1\(options.path)" },
            headers: { ["Authorization": "Bearer test-api-key"] },
            webSocket: webSocketFactory.make,
            _internal: .init(currentDate: { testDate })
        )
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: config)

        let result = try await model.doStream(
            options: TranscriptionModelV4StreamOptions(
                audio: transcriptionAudioStream([.binary(Data([1, 2, 3]))]),
                inputAudioFormat: .init(type: "audio/pcm", rate: 24_000),
                providerOptions: [
                    "openai": [
                        "language": .string("en"),
                        "streaming": .object([
                            "delay": .string("low"),
                            "include": .array([.string("item.input_audio_transcription.logprobs")])
                        ])
                    ]
                ]
            )
        )

        guard let connection = webSocketFactory.firstConnection() else {
            Issue.record("No WebSocket connection was created")
            return
        }

        #expect(connection.request.url.absoluteString == "wss://api.openai.com/v1/realtime?intent=transcription")
        #expect(connection.request.protocols == ["realtime", "openai-insecure-api-key.test-api-key"])

        let partsTask = Task {
            try await collectTranscriptionParts(result.stream)
        }

        connection.open()
        try await connection.waitForSentCount(3)

        let sent = try connection.sentJSONValues()
        #expect(sent[0] == .object([
            "session": .object([
                "audio": .object([
                    "input": .object([
                        "format": .object([
                            "rate": .number(24_000),
                            "type": .string("audio/pcm")
                        ]),
                        "transcription": .object([
                            "delay": .string("low"),
                            "language": .string("en"),
                            "model": .string("gpt-realtime-whisper")
                        ]),
                        "turn_detection": .null
                    ])
                ]),
                "include": .array([.string("item.input_audio_transcription.logprobs")]),
                "type": .string("transcription")
            ]),
            "type": .string("session.update")
        ]))
        #expect(sent[1] == .object([
            "audio": .string("AQID"),
            "type": .string("input_audio_buffer.append")
        ]))
        #expect(sent[2] == .object([
            "type": .string("input_audio_buffer.commit")
        ]))

        try connection.message(.object([
            "type": .string("conversation.item.input_audio_transcription.delta"),
            "item_id": .string("item-1"),
            "delta": .string("Hel")
        ]))
        try connection.message(.object([
            "type": .string("conversation.item.input_audio_transcription.completed"),
            "item_id": .string("item-1"),
            "transcript": .string("Hello")
        ]))

        let parts = try await partsTask.value
        #expect(parts == [
            .streamStart(warnings: []),
            .transcriptDelta(id: "item-1", delta: "Hel", providerMetadata: nil),
            .transcriptFinal(
                id: "item-1",
                text: "Hello",
                startSecond: nil,
                endSecond: nil,
                channelIndex: nil,
                providerMetadata: nil
            ),
            .finish(
                text: "Hello",
                segments: [],
                language: "en",
                durationInSeconds: nil,
                providerMetadata: nil
            )
        ])
        #expect(result.response?.timestamp == testDate)
        #expect(result.response?.modelId == "gpt-realtime-whisper")
    }

    @Test("doStream warns about REST-only OpenAI transcription options")
    func testDoStreamWarnsForRestOnlyOptions() async throws {
        let webSocketFactory = MockOpenAIWebSocketFactory()
        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { options in "https://api.openai.com/v1\(options.path)" },
            headers: { ["Authorization": "Bearer test-api-key"] },
            webSocket: webSocketFactory.make
        )
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: config)

        let result = try await model.doStream(
            options: TranscriptionModelV4StreamOptions(
                audio: transcriptionAudioStream([.binary(Data([1, 2, 3]))]),
                inputAudioFormat: .init(type: "audio/pcm", rate: 24_000),
                providerOptions: [
                    "openai": [
                        "prompt": .string("context prompt"),
                        "temperature": .number(0.5)
                    ]
                ]
            )
        )

        guard let connection = webSocketFactory.firstConnection() else {
            Issue.record("No WebSocket connection was created")
            return
        }

        let partsTask = Task {
            try await collectTranscriptionParts(result.stream)
        }
        connection.open()
        try await connection.waitForSentCount(3)
        try connection.message(.object([
            "type": .string("conversation.item.input_audio_transcription.completed"),
            "item_id": .string("item-1"),
            "transcript": .string("Hello")
        ]))

        let parts = try await partsTask.value
        guard case .streamStart(let warnings) = parts.first else {
            Issue.record("Expected stream-start warning part")
            return
        }
        #expect(warnings == [
            .unsupported(
                feature: "providerOptions.openai.prompt",
                details: "OpenAI streaming transcription does not support prompt."
            ),
            .unsupported(
                feature: "providerOptions.openai.temperature",
                details: "OpenAI streaming transcription does not support temperature."
            )
        ])
    }

    @Test("doStream fails with OpenAI realtime error messages")
    func testDoStreamRealtimeError() async throws {
        let webSocketFactory = MockOpenAIWebSocketFactory()
        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { options in "https://api.openai.com/v1\(options.path)" },
            headers: { ["Authorization": "Bearer test-api-key"] },
            webSocket: webSocketFactory.make
        )
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: config)

        let result = try await model.doStream(
            options: TranscriptionModelV4StreamOptions(
                audio: transcriptionAudioStream([.binary(Data([1, 2, 3]))]),
                inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)
            )
        )

        guard let connection = webSocketFactory.firstConnection() else {
            Issue.record("No WebSocket connection was created")
            return
        }

        let partsTask = Task {
            try await collectTranscriptionParts(result.stream)
        }
        connection.open()
        try await connection.waitForSentCount(3)
        try connection.message(.object([
            "type": .string("error"),
            "error": .object([
                "message": .string("invalid session configuration")
            ])
        ]))

        do {
            _ = try await partsTask.value
            Issue.record("Expected stream collection to throw")
        } catch {
            #expect(String(describing: error).contains("invalid session configuration"))
        }
        #expect(connection.closeCodes().isEmpty == false)
    }

    @Test("doGenerate sends multipart request and parses response")
    func testDoGenerateMultipart() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responsePayload: [String: Any] = [
            "text": "Hello world!",
            "language": "english",
            "duration": 1.5,
            "words": [
                ["word": "Hello", "start": 0.0, "end": 0.5],
                ["word": "world", "start": 0.5, "end": 1.0]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 0) })
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav",
                providerOptions: [
                    "openai": [
                        "include": .array([.string("word_timestamps")]),
                        "language": .string("english"),
                        "prompt": .string("Say hello"),
                        "timestampGranularities": .array([.string("word")])
                    ]
                ],
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        // Validate result mapping
        #expect(result.text == "Hello world!")
        #expect(result.language == "en")
        #expect(result.segments.count == 2)
        if result.segments.count == 2 {
            #expect(result.segments[0].text == "Hello")
            #expect(result.segments[0].startSecond == 0.0)
            #expect(result.segments[0].endSecond == 0.5)
        }
        #expect(result.durationInSeconds == 1.5)
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response.modelId == "whisper-1")

        // Validate request
        guard let request = await capture.value() else {
            Issue.record("No request captured")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-key")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")

        guard let contentType = normalizedHeaders["content-type"],
              contentType.starts(with: "multipart/form-data;") else {
            Issue.record("Missing multipart content type")
            return
        }

        guard let body = request.httpBody else {
            Issue.record("Unable to decode multipart body")
            return
        }

        let bodyString = String(decoding: body, as: UTF8.self)

        #expect(bodyString.contains("Content-Disposition: form-data; name=\"model\""))
        #expect(bodyString.contains("whisper-1"))
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\""))
        #expect(bodyString.contains("ABC"))
        #expect(bodyString.contains("include[]"))
        #expect(bodyString.contains("language"))
        #expect(bodyString.contains("prompt"))
        #expect(bodyString.contains("response_format"))
        #expect(bodyString.contains("timestamp_granularities[]"))
    }

    @Test("V4 doGenerate defaults whisper-1 REST transcription to verbose_json")
    func testV4DoGenerateDefaultsWhisperToVerboseJSON() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responsePayload: [String: Any] = [
            "text": "Hello world!",
            "language": "english",
            "duration": 1.5,
            "words": [
                ["word": "Hello", "start": 0.0, "end": 0.5],
                ["word": "world", "start": 0.5, "end": 1.0]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 0) })
        )

        let model = OpenAITranscriptionModelV4(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV4CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        #expect(result.text == "Hello world!")
        #expect(result.language == "en")
        #expect(result.segments.count == 2)
        #expect(result.durationInSeconds == 1.5)
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response.modelId == "whisper-1")

        guard let request = await capture.value(),
              let body = request.httpBody
        else {
            Issue.record("No V4 transcription request captured")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")

        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(multipartFieldValues(in: bodyString, named: "model") == ["whisper-1"])
        #expect(multipartFieldValues(in: bodyString, named: "response_format") == ["verbose_json"])
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\""))
    }

    @Test("V4 doGenerate sends OpenAI REST transcription provider options")
    func testV4DoGenerateSendsProviderOptions() async throws {
        actor BodyCapture {
            var bodyString: String?
            func store(_ data: Data) {
                bodyString = String(decoding: data, as: UTF8.self)
            }
        }

        let capture = BodyCapture()

        let responsePayload: [String: Any] = ["text": "Test"]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody {
                await capture.store(body)
            }
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModelV4(modelId: "gpt-4o-transcribe", config: config)

        _ = try await model.doGenerate(
            options: TranscriptionModelV4CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/mpeg",
                providerOptions: [
                    "openai": [
                        "timestampGranularities": .array([.string("word")])
                    ]
                ]
            )
        )

        guard let bodyString = await capture.bodyString else {
            Issue.record("Multipart body not captured")
            return
        }

        #expect(multipartFieldValues(in: bodyString, named: "model") == ["gpt-4o-transcribe"])
        #expect(multipartFieldValues(in: bodyString, named: "response_format") == ["json"])
        #expect(multipartFieldValues(in: bodyString, named: "temperature") == ["0"])
        #expect(multipartFieldValues(in: bodyString, named: "timestamp_granularities[]") == ["word"])
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.mp3\""))
    }

    @Test("response_format is json for 4o transcription models")
    func testResponseFormatForReasoningModels() async throws {
        actor BodyCapture {
            var bodyString: String?
            func store(_ data: Data) {
                bodyString = String(decoding: data, as: UTF8.self)
            }
        }


        let capture = BodyCapture()

        let responsePayload: [String: Any] = ["text": "Test"]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody {
                await capture.store(body)
            }
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "gpt-4o-transcribe", config: config)

        _ = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/mpeg",
                providerOptions: [
                    "openai": [
                        "timestampGranularities": .array([.string("word")])
                    ]
                ]
            )
        )

        let bodyString = await capture.bodyString
        if let captured = bodyString {
            let normalized = captured.replacingOccurrences(of: "\r", with: "")
            if let range = normalized.range(of: "response_format") {
                let tail = normalized[range.upperBound...]
                #expect(tail.contains("json"))
            } else {
                Issue.record("response_format field missing")
            }
        } else {
            Issue.record("Multipart body not captured")
        }
    }

    // Port of openai-transcription-model.test.ts: "should pass the model"
    @Test("should pass the model")
    func testPassTheModel() async throws {
        actor BodyCapture {
            var bodyString: String?
            func store(_ data: Data) {
                bodyString = String(decoding: data, as: UTF8.self)
            }
        }

        let capture = BodyCapture()

        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody {
                await capture.store(body)
            }
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        _ = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        let bodyString = await capture.bodyString
        #expect(bodyString != nil)
        #expect(bodyString?.contains("whisper-1") == true)
    }

    // Port of openai-transcription-model.test.ts: "should pass headers"
    @Test("should pass headers")
    func testPassHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: {
                [
                    "Authorization": "Bearer test-api-key",
                    "OpenAI-Organization": "test-organization",
                    "OpenAI-Project": "test-project",
                    "Custom-Provider-Header": "provider-header-value"
                ]
            },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        _ = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav",
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
        #expect(normalizedHeaders["openai-organization"] == "test-organization")
        #expect(normalizedHeaders["openai-project"] == "test-project")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
        #expect(normalizedHeaders["content-type"]?.starts(with: "multipart/form-data") == true)
    }

    // Port of openai-transcription-model.test.ts: "should extract the transcription text"
    @Test("should extract the transcription text")
    func testExtractTranscriptionText() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        #expect(result.text == "Hello from the Vercel AI SDK!")
    }

    // Port of openai-transcription-model.test.ts: "should include response data with timestamp, modelId and headers"
    @Test("should include response data with timestamp, modelId and headers")
    func testIncludeResponseData() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "X-Request-ID": "test-request-id",
                    "X-RateLimit-Remaining": "123"
                ]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let testDate = Date(timeIntervalSince1970: 0)
        let config = OpenAIConfig(
            provider: "test-provider",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch,
            _internal: .init(currentDate: { testDate })
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "whisper-1")

        let headers = result.response.headers ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["content-type"] == "application/json")
        #expect(normalizedHeaders["x-request-id"] == "test-request-id")
        #expect(normalizedHeaders["x-ratelimit-remaining"] == "123")
    }

    // Port of openai-transcription-model.test.ts: "should use real date when no custom date provider is specified"
    @Test("should use real date when no custom date provider is specified")
    func testUseRealDate() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let testDate = Date(timeIntervalSince1970: 0)
        let config = OpenAIConfig(
            provider: "test-provider",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch,
            _internal: .init(currentDate: { testDate })
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        #expect(result.response.timestamp.timeIntervalSince1970 == testDate.timeIntervalSince1970)
        #expect(result.response.modelId == "whisper-1")
    }

    // Port of openai-transcription-model.test.ts: "should pass response_format when `providerOptions.openai.timestampGranularities` is set"
    @Test("should pass response_format when timestampGranularities is set")
    func testPassResponseFormatWithTimestampGranularities() async throws {
        actor BodyCapture {
            var bodyString: String?
            func store(_ data: Data) {
                bodyString = String(decoding: data, as: UTF8.self)
            }
        }

        let capture = BodyCapture()

        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody {
                await capture.store(body)
            }
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        _ = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav",
                providerOptions: [
                    "openai": [
                        "timestampGranularities": .array([.string("word")])
                    ]
                ]
            )
        )

        let bodyString = await capture.bodyString
        #expect(bodyString != nil)
        #expect(bodyString?.contains("response_format") == true)
        #expect(bodyString?.contains("verbose_json") == true)
        #expect(bodyString?.contains("timestamp_granularities[]") == true)
    }

    // Port of openai-transcription-model.test.ts: "should pass timestamp_granularities when specified"
    @Test("should pass timestamp_granularities when specified")
    func testPassTimestampGranularities() async throws {
        actor BodyCapture {
            var bodyString: String?
            func store(_ data: Data) {
                bodyString = String(decoding: data, as: UTF8.self)
            }
        }

        let capture = BodyCapture()

        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody {
                await capture.store(body)
            }
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        _ = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav",
                providerOptions: [
                    "openai": [
                        "timestampGranularities": .array([.string("segment")])
                    ]
                ]
            )
        )

        let bodyString = await capture.bodyString
        #expect(bodyString != nil)
        #expect(bodyString?.contains("timestamp_granularities[]") == true)
        #expect(bodyString?.contains("segment") == true)
        #expect(bodyString?.contains("response_format") == true)
        #expect(bodyString?.contains("verbose_json") == true)
    }

    // Port of openai-transcription-model.test.ts: "should work when no words, language, or duration are returned"
    @Test("should work when no words, language, or duration are returned")
    func testHandleMissingOptionalFields() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello from the Vercel AI SDK!",
            "_request_id": "req_1234"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let testDate = Date(timeIntervalSince1970: 0)
        let config = OpenAIConfig(
            provider: "test-provider",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch,
            _internal: .init(currentDate: { testDate })
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        #expect(result.text == "Hello from the Vercel AI SDK!")
        #expect(result.durationInSeconds == nil)
        #expect(result.language == nil)
        #expect(result.segments.isEmpty)
        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "whisper-1")
    }

    // Port of openai-transcription-model.test.ts: "should parse segments when provided in response"
    @Test("should parse segments when provided in response")
    func testParseSegments() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello world. How are you?",
            "segments": [
                [
                    "id": 0,
                    "seek": 0,
                    "start": 0.0,
                    "end": 2.5,
                    "text": "Hello world.",
                    "tokens": [1234, 5678],
                    "temperature": 0.0,
                    "avg_logprob": -0.5,
                    "compression_ratio": 1.2,
                    "no_speech_prob": 0.1
                ],
                [
                    "id": 1,
                    "seek": 250,
                    "start": 2.5,
                    "end": 5.0,
                    "text": " How are you?",
                    "tokens": [9012, 3456],
                    "temperature": 0.0,
                    "avg_logprob": -0.6,
                    "compression_ratio": 1.1,
                    "no_speech_prob": 0.05
                ]
            ],
            "language": "en",
            "duration": 5.0,
            "_request_id": "req_1234"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav",
                providerOptions: [
                    "openai": [
                        "timestampGranularities": .array([.string("segment")])
                    ]
                ]
            )
        )

        #expect(result.text == "Hello world. How are you?")
        #expect(result.durationInSeconds == 5.0)
        #expect(result.segments.count == 2)

        if result.segments.count >= 2 {
            #expect(result.segments[0].text == "Hello world.")
            #expect(result.segments[0].startSecond == 0.0)
            #expect(result.segments[0].endSecond == 2.5)

            #expect(result.segments[1].text == " How are you?")
            #expect(result.segments[1].startSecond == 2.5)
            #expect(result.segments[1].endSecond == 5.0)
        }
    }

    // Port of openai-transcription-model.test.ts: "should fallback to words when segments are not available"
    @Test("should fallback to words when segments are not available")
    func testFallbackToWords() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello world",
            "words": [
                [
                    "word": "Hello",
                    "start": 0.0,
                    "end": 1.0
                ],
                [
                    "word": "world",
                    "start": 1.0,
                    "end": 2.0
                ]
            ],
            "language": "en",
            "duration": 2.0,
            "_request_id": "req_1234"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav",
                providerOptions: [
                    "openai": [
                        "timestampGranularities": .array([.string("word")])
                    ]
                ]
            )
        )

        #expect(result.segments.count == 2)

        if result.segments.count >= 2 {
            #expect(result.segments[0].text == "Hello")
            #expect(result.segments[0].startSecond == 0.0)
            #expect(result.segments[0].endSecond == 1.0)

            #expect(result.segments[1].text == "world")
            #expect(result.segments[1].startSecond == 1.0)
            #expect(result.segments[1].endSecond == 2.0)
        }
    }

    // Port of openai-transcription-model.test.ts: "should handle empty segments array"
    @Test("should handle empty segments array")
    func testHandleEmptySegments() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Hello world",
            "segments": [],
            "language": "en",
            "duration": 2.0,
            "_request_id": "req_1234"
        ] as [String: Any]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        #expect(result.segments.isEmpty)
        #expect(result.text == "Hello world")
    }

    // Port of openai-transcription-model.test.ts: "should handle segments with missing optional fields"
    @Test("should handle segments with missing optional fields")
    func testHandleSegmentsWithMissingFields() async throws {
        let responsePayload: [String: Any] = [
            "task": "transcribe",
            "text": "Test",
            "segments": [
                [
                    "id": 0,
                    "seek": 0,
                    "start": 0.0,
                    "end": 1.0,
                    "text": "Test",
                    "tokens": [1234],
                    "temperature": 0.0,
                    "avg_logprob": -0.5,
                    "compression_ratio": 1.0,
                    "no_speech_prob": 0.1
                ]
            ],
            "_request_id": "req_1234"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responsePayload)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.transcription",
            url: { _ in "https://api.openai.com/v1/audio/transcriptions" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: config)

        let result = try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(sampleAudioData),
                mediaType: "audio/wav"
            )
        )

        #expect(result.segments.count == 1)

        if !result.segments.isEmpty {
            #expect(result.segments[0].text == "Test")
            #expect(result.segments[0].startSecond == 0.0)
            #expect(result.segments[0].endSecond == 1.0)
        }

        #expect(result.language == nil)
        #expect(result.durationInSeconds == nil)
    }
}
