import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalSpeechModel")
struct FalSpeechModelTests {
    private let modelId: FalSpeechModelId = "fal-ai/minimax/speech-02-hd"
    private let generateURL = "https://fal.run/fal-ai/minimax/speech-02-hd"
    private let audioURL = "https://fal.media/files/test.mp3"

    private actor RequestCapture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func all() -> [URLRequest] { requests }
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
    ) -> FalSpeechModel {
        FalSpeechModel(
            modelId: modelId,
            config: FalConfig(
                provider: "fal.speech",
                url: { options in options.path },
                headers: headers,
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    @Test("passes text and default output_format")
    func passesTextAndDefaultOutputFormat() async throws {
        let capture = RequestCapture()
        let audioBytes = Data(repeating: 0x1, count: 100)
        let responseData = try jsonData([
            "audio": ["url": audioURL],
            "duration_ms": 1234
        ])

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = request.url?.absoluteString ?? ""
            if url == generateURL {
                return FetchResponse(
                    body: .data(responseData),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == audioURL {
                return FetchResponse(
                    body: .data(audioBytes),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "audio/mp3"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(text: "Hello from the AI SDK!"))

        guard let request = await capture.first(),
              let body = request.httpBody
        else {
            Issue.record("Missing request capture")
            return
        }

        let requestBody = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(requestBody == .object([
            "text": .string("Hello from the AI SDK!"),
            "output_format": .string("url")
        ]))
    }

    @Test("passes provider and request headers")
    func passesHeaders() async throws {
        let capture = RequestCapture()
        let responseData = try jsonData([
            "audio": ["url": audioURL]
        ])

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = request.url?.absoluteString ?? ""
            if url == generateURL {
                return FetchResponse(
                    body: .data(responseData),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == audioURL {
                return FetchResponse(
                    body: .data(Data([1, 2, 3])),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "audio/mp3"]
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

        _ = try await provider.speech(modelId: modelId).doGenerate(options: .init(
            text: "Hello from the AI SDK!",
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

    @Test("returns downloaded audio data")
    func returnsAudioData() async throws {
        let audioBytes = Data(repeating: 0xAA, count: 32)
        let responseData = try jsonData([
            "audio": ["url": audioURL],
            "duration_ms": 1234
        ])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == generateURL {
                return FetchResponse(
                    body: .data(responseData),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == audioURL {
                return FetchResponse(
                    body: .data(audioBytes),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "audio/mp3"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(text: "Hello from the AI SDK!"))

        #expect(result.audio == .binary(audioBytes))
    }

    @Test("includes response metadata with timestamp/modelId/headers")
    func includesResponseMetadata() async throws {
        let responseData = try jsonData([
            "audio": ["url": audioURL]
        ])
        let testDate = Date(timeIntervalSince1970: 0)

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == generateURL {
                return FetchResponse(
                    body: .data(responseData),
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
            if url == audioURL {
                return FetchResponse(
                    body: .data(Data([1, 2, 3])),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "audio/mp3"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch, currentDate: { testDate })
        let result = try await model.doGenerate(options: .init(text: "Hello from the AI SDK!"))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == modelId.rawValue)
        #expect(result.response.headers?["x-request-id"] == "test-request-id")
    }

    @Test("adds warnings for unsupported settings")
    func addsWarningsForUnsupportedSettings() async throws {
        let responseData = try jsonData([
            "audio": ["url": audioURL]
        ])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == generateURL {
                return FetchResponse(
                    body: .data(responseData),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }
            if url == audioURL {
                return FetchResponse(
                    body: .data(Data([1, 2, 3])),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "audio/mp3"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(
            text: "Hello from the AI SDK!",
            outputFormat: "wav",
            language: "en"
        ))

        #expect(result.warnings.count == 2)
        #expect(result.warnings.contains { warning in
            if case .unsupported(feature: "language", _) = warning {
                return true
            }
            return false
        })
        #expect(result.warnings.contains { warning in
            if case .unsupported(feature: "outputFormat", _) = warning {
                return true
            }
            return false
        })
    }
}
