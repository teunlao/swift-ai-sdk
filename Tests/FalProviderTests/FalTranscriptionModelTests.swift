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

    @Test("provider defaults, nulls and fractional values follow the transcription schema", arguments: ["defaults", "nulls", "numbers"])
    func providerOptions(mode: String) async throws {
        let capture = RequestCapture()
        let fetch: FetchFunction = { request in
            await capture.append(request)
            let body = request.httpMethod == "POST" ? #"{"request_id":"test-id"}"# : #"{"text":"done"}"#
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: makeHTTPResponse(
                url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"]
            ))
        }
        let falOptions: [String: JSONValue]
        var expected: [String: JSONValue] = [
            "audio_url": .string("data:audio/wav;base64,AQID"), "task": .string("transcribe"), "diarize": .bool(true),
        ]
        switch mode {
        case "nulls":
            falOptions = ["language": .null, "diarize": .null, "chunkLevel": .null, "version": .null,
                          "batchSize": .null, "numSpeakers": .null, "task": .string("translate")]
            expected["language"] = .null
            expected["chunk_level"] = .string("word")
        case "numbers":
            falOptions = ["batchSize": .number(1.25), "numSpeakers": .number(2.5), "diarize": .bool(false), "chunkLevel": .string("word")]
            expected["language"] = .string("en")
            expected["chunk_level"] = .string("word")
            expected["version"] = .string("3")
            expected["batch_size"] = .number(1.25)
            expected["num_speakers"] = .number(2.5)
            expected["diarize"] = .bool(false)
        default:
            falOptions = [:]
            expected["language"] = .string("en")
            expected["chunk_level"] = .string("segment")
            expected["version"] = .string("3")
            expected["batch_size"] = .number(64)
        }
        let result = try await makeModel(fetch: fetch).doGenerate(options: .init(
            audio: .base64("AQID"), mediaType: "audio/wav", providerOptions: ["fal": falOptions]
        ))
        let request = try #require(await capture.first())
        #expect(try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody)) == .object(expected))
        #expect(result.text == "done")
    }

    @Test("timestamp extraction uses the first two positions, including missing endpoints")
    func timestampPositions() async throws {
        let fetch: FetchFunction = { request in
            let body = request.httpMethod == "POST" ? #"{"request_id":"test-id"}"# : #"{"text":"abc","chunks":[{"text":"a","timestamp":[1,2,99]},{"text":"b","timestamp":[3]},{"text":"c","timestamp":null}]}"#
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: makeHTTPResponse(
                url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"]
            ))
        }
        let result = try await makeModel(fetch: fetch).doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav"))
        #expect(result.segments == [
            .init(text: "a", startSecond: 1, endSecond: 2),
            .init(text: "b", startSecond: 3, endSecond: 0),
            .init(text: "c", startSecond: 0, endSecond: 0),
        ])
        #expect(result.durationInSeconds == nil)
    }

    @Test("invalid transcription versions fail before the HTTP request")
    func invalidVersion() async throws {
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await makeModel().doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav",
                                                              providerOptions: ["fal": ["version": .string("2")]]))
        }
    }

    @Test("polling failures retain the API error payload and HTTP context")
    func pollingFailure() async throws {
        let fetch: FetchFunction = { request in
            let isPost = request.httpMethod == "POST"
            let body = isPost ? #"{"request_id":"test-id"}"# : #"{"error":{"message":"quota exceeded","code":429.5}}"#
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: makeHTTPResponse(
                url: request.url!, statusCode: isPost ? 200 : 429,
                headers: ["Content-Type": "application/json", "x-request-id": "failed-job"]
            ))
        }
        do {
            _ = try await makeModel(fetch: fetch).doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav"))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "quota exceeded")
            #expect(error.statusCode == 429)
            #expect(error.responseHeaders?["x-request-id"] == "failed-job")
        }
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
