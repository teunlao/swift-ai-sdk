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
}
