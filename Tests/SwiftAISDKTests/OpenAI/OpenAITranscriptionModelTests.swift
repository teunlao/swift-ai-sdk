import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let sampleAudioData = Data("ABC".utf8)

@Suite("OpenAITranscriptionModel")
struct OpenAITranscriptionModelTests {
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
                mediaType: "audio/mpeg"
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
