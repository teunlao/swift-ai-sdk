import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalTranscriptionModel")
struct FalTranscriptionModelTests {
    private let modelId: FalTranscriptionModelId = "wizper"
    private let queueURL = "https://queue.fal.run/fal-ai/wizper"
    private let statusURL = "https://queue.fal.run/fal-ai/wizper/requests/test-id"

    private actor RequestCapture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func first() -> URLRequest? { requests.first }
    }

    private func makeHTTPResponse(url: URL, statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func makeModel(
        headers: @escaping @Sendable () -> [String: String?] = { ["authorization": "Key test-api-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) }
    ) -> FalTranscriptionModel {
        FalTranscriptionModel(
            modelId: modelId,
            config: FalConfig(
                provider: "fal.transcription",
                url: { options in options.path },
                headers: headers,
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private func decodeRequestBodyObject(_ request: URLRequest) throws -> [String: Any] {
        guard let body = request.httpBody,
              let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            throw NSError(domain: "FalTranscriptionModelTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing request body"])
        }
        return object
    }

    @Test("passes expected queue request body")
    func passesExpectedQueueRequestBody() async throws {
        let capture = RequestCapture()
        let queueResponse = try jsonData([
            "request_id": "test-id"
        ])
        let statusResponse = try jsonData([
            "text": "Hello world!",
            "chunks": [
                ["text": "Hello", "timestamp": [0, 1]],
                ["text": " world!", "timestamp": [1, 2]]
            ],
            "inferred_languages": ["en"]
        ])

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = request.url?.absoluteString ?? ""
            if url == queueURL {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == statusURL {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            audio: .binary(Data([0x01, 0x02, 0x03])),
            mediaType: "audio/wav"
        ))

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }

        let body = try decodeRequestBodyObject(request)
        #expect(body["task"] as? String == "transcribe")
        #expect(body["diarize"] as? Bool == true)
        #expect(body["chunk_level"] as? String == "word")
        #expect((body["audio_url"] as? String)?.hasPrefix("data:audio/wav;base64,") == true)
    }

    @Test("passes provider and request headers")
    func passesHeaders() async throws {
        let capture = RequestCapture()
        let queueResponse = try jsonData(["request_id": "test-id"])
        let statusResponse = try jsonData(["text": "Hello world!"])

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = request.url?.absoluteString ?? ""
            if url == queueURL {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == statusURL {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let provider = createFal(settings: .init(
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider.transcription(modelId: modelId).doGenerate(options: .init(
            audio: .binary(Data([0x01])),
            mediaType: "audio/wav",
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }

        let normalizedHeaders = Dictionary(
            uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }
        )
        #expect(normalizedHeaders["authorization"] == "Key test-api-key")
        #expect(normalizedHeaders["content-type"] == "application/json")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
    }

    @Test("extracts transcription text and timing data")
    func extractsTranscriptionTextAndTiming() async throws {
        let queueResponse = try jsonData(["request_id": "test-id"])
        let statusResponse = try jsonData([
            "text": "Hello world!",
            "chunks": [
                ["text": "Hello", "timestamp": [0, 1]],
                ["text": " ", "timestamp": [1, 1.5]],
                ["text": "world!", "timestamp": [1.5, 3]]
            ],
            "inferred_languages": ["en"]
        ])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == queueURL {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == statusURL {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(
            audio: .binary(Data([0x01, 0x02])),
            mediaType: "audio/wav"
        ))

        #expect(result.text == "Hello world!")
        #expect(result.segments.count == 3)
        #expect(result.language == "en")
        #expect(result.durationInSeconds == 3)
    }

    @Test("includes response metadata with timestamp/modelId/headers")
    func includesResponseMetadata() async throws {
        let queueResponse = try jsonData(["request_id": "test-id"])
        let statusResponse = try jsonData(["text": "Hello world!"])
        let testDate = Date(timeIntervalSince1970: 0)

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == queueURL {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == statusURL {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/json",
                            "x-request-id": "test-request-id"
                        ]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch, currentDate: { testDate })
        let result = try await model.doGenerate(options: .init(
            audio: .binary(Data([0x01])),
            mediaType: "audio/wav"
        ))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == modelId.rawValue)
        #expect(result.response.headers?["x-request-id"] == "test-request-id")
    }

    @Test("continues polling after in-progress queue status")
    func continuesPollingAfterInProgressStatus() async throws {
        actor Counter {
            var statusCalls = 0
            func nextStatusCall() -> Int {
                statusCalls += 1
                return statusCalls
            }
        }

        let counter = Counter()
        let queueResponse = try jsonData(["request_id": "test-id"])
        let inProgressBody = try jsonData(["detail": "Request is still in progress"])
        let finalBody = try jsonData(["text": "done"])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == queueURL {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == statusURL {
                let callNumber = await counter.nextStatusCall()
                if callNumber == 1 {
                    return FetchResponse(
                        body: .data(inProgressBody),
                        urlResponse: makeHTTPResponse(
                            url: request.url!,
                            statusCode: 400,
                            headers: ["Content-Type": "application/json"]
                        )
                    )
                }

                return FetchResponse(
                    body: .data(finalBody),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(
            audio: .binary(Data([0x01])),
            mediaType: "audio/wav"
        ))

        #expect(result.text == "done")
    }
}
