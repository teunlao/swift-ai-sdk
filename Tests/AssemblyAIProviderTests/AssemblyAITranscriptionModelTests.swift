import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import AssemblyAIProvider

@Suite("AssemblyAITranscriptionModel", .serialized)
struct AssemblyAITranscriptionModelTests {
    private static let audioData = Data([0x01, 0x02, 0x03, 0x04])

    private actor RequestCapture {
        private(set) var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func all() -> [URLRequest] { requests }
    }

    private static func encodeJSON(_ json: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: json)
    }

    private static func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String] = ["Content-Type": "application/json"]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private static func makeFetch(capture: RequestCapture, finalHeaders: [String: String]? = nil) -> FetchFunction {
        { request in
            await capture.append(request)

            guard let url = request.url else {
                throw APICallError(message: "Missing URL", url: "<missing>", requestBodyValues: nil)
            }

            switch url.path {
            case "/v2/upload":
                let body = encodeJSON([
                    "id": "9ea68fd3-f953-42c1-9742-976c447fb463",
                    "upload_url": "https://storage.assemblyai.com/mock-upload-url",
                ])
                return FetchResponse(body: .data(body), urlResponse: makeHTTPResponse(url: url))

            case "/v2/transcript":
                let body = encodeJSON([
                    "id": "9ea68fd3-f953-42c1-9742-976c447fb463",
                    "status": "queued",
                ])
                return FetchResponse(body: .data(body), urlResponse: makeHTTPResponse(url: url))

            case "/v2/transcript/9ea68fd3-f953-42c1-9742-976c447fb463":
                var headers = finalHeaders ?? [:]
                if headers["Content-Type"] == nil && headers["content-type"] == nil {
                    headers["Content-Type"] = "application/json"
                }

                let body = encodeJSON([
                    "id": "9ea68fd3-f953-42c1-9742-976c447fb463",
                    "audio_url": "https://assembly.ai/test.mp3",
                    "status": "completed",
                    "language_code": "en_us",
                    "audio_duration": 281,
                    "text": "Hello, world!",
                    "words": [
                        ["start": 250, "end": 650, "text": "Hello,"],
                        ["start": 730, "end": 1022, "text": "world"],
                    ],
                ])

                return FetchResponse(
                    body: .data(body),
                    urlResponse: makeHTTPResponse(url: url, headers: headers)
                )

            default:
                throw APICallError(message: "Unexpected path", url: url.absoluteString, requestBodyValues: nil)
            }
        }
    }

    @Test("should pass the model")
    func shouldPassTheModel() async throws {
        let capture = RequestCapture()
        let provider = createAssemblyAI(settings: .init(apiKey: "test-api-key", fetch: Self.makeFetch(capture: capture)))
        let model = provider.transcription(modelId: .best)

        _ = try await model.doGenerate(options: .init(audio: .binary(Self.audioData), mediaType: "audio/wav"))

        let requests = await capture.all()
        #expect(requests.count == 3)

        guard let submitBody = requests[safe: 1]?.httpBody else {
            Issue.record("Expected submit request body")
            return
        }

        let parsed = try JSONDecoder().decode(JSONValue.self, from: submitBody)
        guard case .object(let dict) = parsed else {
            Issue.record("Expected submit request JSON object")
            return
        }

        #expect(dict["audio_url"] == .string("https://storage.assemblyai.com/mock-upload-url"))
        #expect(dict["speech_model"] == .string("best"))
    }

    @Test("should pass headers")
    func shouldPassHeaders() async throws {
        let capture = RequestCapture()
        let provider = createAssemblyAI(settings: .init(
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: Self.makeFetch(capture: capture)
        ))

        let model = provider.transcription(modelId: .best)
        _ = try await model.doGenerate(options: .init(
            audio: .binary(Self.audioData),
            mediaType: "audio/wav",
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        let requests = await capture.all()
        guard let upload = requests.first else {
            Issue.record("Expected upload request")
            return
        }

        let headers = upload.allHTTPHeaderFields ?? [:]
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })

        #expect(normalized["authorization"] == "test-api-key")
        #expect(normalized["content-type"] == "application/octet-stream")
        #expect(normalized["custom-provider-header"] == "provider-header-value")
        #expect(normalized["custom-request-header"] == "request-header-value")
        #expect((normalized["user-agent"] ?? "").contains("ai-sdk/assemblyai/\(ASSEMBLYAI_VERSION)"))
    }

    @Test("should extract the transcription text")
    func shouldExtractTheTranscriptionText() async throws {
        let capture = RequestCapture()
        let provider = createAssemblyAI(settings: .init(apiKey: "test-api-key", fetch: Self.makeFetch(capture: capture)))
        let model = provider.transcription(modelId: .best)

        let result = try await model.doGenerate(options: .init(audio: .binary(Self.audioData), mediaType: "audio/wav"))
        #expect(result.text == "Hello, world!")
    }

    @Test("should include response data with timestamp, modelId and headers")
    func shouldIncludeResponseDataWithTimestampModelIdAndHeaders() async throws {
        let capture = RequestCapture()
        let testDate = Date(timeIntervalSince1970: 0)

        let fetch = Self.makeFetch(
            capture: capture,
            finalHeaders: [
                "x-request-id": "test-request-id",
                "x-ratelimit-remaining": "123",
            ]
        )

        let model = AssemblyAITranscriptionModel(
            modelId: .best,
            config: .init(
                provider: "test-provider",
                url: { options in "https://api.assemblyai.com\(options.path)" },
                headers: { [:] },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: .init(audio: .binary(Self.audioData), mediaType: "audio/wav"))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "best")
        #expect(result.response.headers?["content-type"] == "application/json")
        #expect(result.response.headers?["x-request-id"] == "test-request-id")
        #expect(result.response.headers?["x-ratelimit-remaining"] == "123")
    }

    @Test("should use real date when no custom date provider is specified")
    func shouldUseRealDateWhenNoCustomDateProviderIsSpecified() async throws {
        let capture = RequestCapture()
        let provider = createAssemblyAI(settings: .init(apiKey: "test-api-key", fetch: Self.makeFetch(capture: capture)))
        let model = provider.transcription(modelId: .best)

        let before = Date()
        let result = try await model.doGenerate(options: .init(audio: .binary(Self.audioData), mediaType: "audio/wav"))
        let after = Date()

        #expect(result.response.timestamp >= before)
        #expect(result.response.timestamp <= after)
        #expect(result.response.modelId == "best")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

