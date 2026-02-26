import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import XAIProvider

@Suite("XAIVideoModel")
struct XAIVideoModelTests {
    private let prompt = "A chicken flying into the sunset"
    private let baseURL = "https://api.example.com"

    private var createGenerationsURL: String { "\(baseURL)/videos/generations" }
    private var createEditsURL: String { "\(baseURL)/videos/edits" }
    private var statusURL: String { "\(baseURL)/videos/req-123" }

    private static func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [])
    }

    private static func httpResponse(url: URL, statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private actor HTTPStub {
        typealias Handler = @Sendable (_ request: URLRequest, _ callNumber: Int) async throws -> FetchResponse

        struct Call: Sendable {
            let method: String
            let url: String
            let headers: [String: String]
            let body: JSONValue?
        }

        private var handlers: [String: Handler] = [:]
        private var calls: [Call] = []
        private var callCountByKey: [String: Int] = [:]

        func setJSON(
            method: String,
            url: String,
            statusCode: Int = 200,
            body: Any,
            headers: [String: String]? = nil
        ) async throws {
            let data = try XAIVideoModelTests.jsonData(body)
            let headerFields: [String: String] = {
                var base: [String: String] = [
                    "Content-Type": "application/json",
                    "Content-Length": String(data.count),
                ]
                if let headers {
                    for (k, v) in headers { base[k] = v }
                }
                return base
            }()

            setHandler(method: method, url: url) { request, _ in
                FetchResponse(
                    body: .data(data),
                    urlResponse: XAIVideoModelTests.httpResponse(url: request.url!, statusCode: statusCode, headers: headerFields)
                )
            }
        }

        func setHandler(method: String, url: String, handler: @escaping Handler) {
            handlers["\(method.uppercased()) \(url)"] = handler
        }

        func handle(_ request: URLRequest) async throws -> FetchResponse {
            let method = request.httpMethod ?? "GET"
            let url = request.url?.absoluteString ?? ""
            let key = "\(method.uppercased()) \(url)"

            let callNumber = (callCountByKey[key] ?? 0) + 1
            callCountByKey[key] = callNumber

            let headers = request.allHTTPHeaderFields ?? [:]
            let body: JSONValue?
            if let data = request.httpBody {
                body = try? JSONDecoder().decode(JSONValue.self, from: data)
            } else {
                body = nil
            }
            calls.append(Call(method: method, url: url, headers: headers, body: body))

            guard let handler = handlers[key] else {
                throw TestError(message: "Unexpected request: \(key)")
            }

            return try await handler(request, callNumber)
        }

        func call(at index: Int) -> Call? {
            guard index >= 0, index < calls.count else { return nil }
            return calls[index]
        }

        func count() -> Int { calls.count }
    }

    private struct TestError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private var createVideoResponse: [String: Any] {
        ["request_id": "req-123"]
    }

    private var doneStatusResponse: [String: Any] {
        [
            "status": "done",
            "video": [
                "url": "https://vidgen.x.ai/output/video-001.mp4",
                "duration": 5,
                "respect_moderation": true,
            ],
            "model": "grok-imagine-video",
        ]
    }

    private var defaultProviderOptions: SharedV3ProviderOptions {
        [
            "xai": [
                "pollIntervalMs": 10,
                "pollTimeoutMs": 5_000,
            ]
        ]
    }

    private var defaultOptions: VideoModelV3CallOptions {
        VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: defaultProviderOptions
        )
    }

    private func makeModel(
        headers: (@Sendable () -> [String: String?])? = { ["api-key": "test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> XAIVideoModel {
        XAIVideoModel(
            modelId: .grokImagineVideo,
            config: XAIVideoModelConfig(
                provider: "xai.video",
                baseURL: baseURL,
                headers: headers ?? { [:] },
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    @Test("constructor exposes correct provider and model information")
    func constructorInfo() throws {
        let model = makeModel()
        #expect(model.provider == "xai.video")
        #expect(model.modelId == "grok-imagine-video")
        #expect(model.specificationVersion == "v3")

        switch model.maxVideosPerCall {
        case .value(let value):
            #expect(value == 1)
        case .default, .function:
            Issue.record("Expected fixed maxVideosPerCall == 1")
        }
    }

    @Test("sends correct request body with model and prompt")
    func requestBodyMinimal() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: defaultOptions)

        guard let call = await stub.call(at: 0) else {
            Issue.record("Missing create call")
            return
        }

        #expect(call.method.uppercased() == "POST")
        #expect(call.url == createGenerationsURL)
        #expect(call.body == .object([
            "model": .string("grok-imagine-video"),
            "prompt": .string(prompt),
        ]))
    }

    @Test("polls the correct status URL")
    func pollsCorrectStatusURL() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: defaultOptions)

        guard let call = await stub.call(at: 1) else {
            Issue.record("Missing poll call")
            return
        }

        #expect(call.method.uppercased() == "GET")
        #expect(call.url == statusURL)
    }

    @Test("sends duration in request body")
    func sendsDuration() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            duration: 10,
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["duration"] == 10)
    }

    @Test("sends aspect_ratio in request body")
    func sendsAspectRatio() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            aspectRatio: "9:16",
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["aspect_ratio"] == "9:16")
    }

    @Test("maps SDK resolution 1280x720 to 720p")
    func resolutionMaps720p() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            resolution: "1280x720",
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["resolution"] == "720p")
    }

    @Test("maps SDK resolution 854x480 to 480p")
    func resolutionMaps480p() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            resolution: "854x480",
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["resolution"] == "480p")
    }

    @Test("prefers provider option resolution over SDK resolution")
    func providerResolutionOverridesSDKResolution() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let providerOptions: SharedV3ProviderOptions = [
            "xai": [
                "resolution": "480p",
                "pollIntervalMs": 10,
                "pollTimeoutMs": 5_000,
            ]
        ]

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            resolution: "1280x720",
            providerOptions: providerOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["resolution"] == "480p")
    }

    @Test("warns for unrecognized resolution format")
    func warnsUnrecognizedResolution() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            resolution: "1920x1080",
            providerOptions: defaultProviderOptions
        ))

        #expect(result.warnings.contains(where: { warning in
            if case .unsupported(feature: "resolution", details: _) = warning { return true }
            return false
        }))
    }

    @Test("sends image object from URL-based image input")
    func sendsImageURL() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/image.png", providerOptions: nil),
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["image"] == .object(["url": "https://example.com/image.png"]))
    }

    @Test("sends image object with data URI from file data")
    func sendsImageDataURIFromBinary() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let imageData = Data([137, 80, 78, 71]) // PNG magic bytes

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .file(mediaType: "image/png", data: .binary(imageData), providerOptions: nil),
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["image"] == .object(["url": "data:image/png;base64,iVBORw=="]))
    }

    @Test("sends image object with data URI from base64 string")
    func sendsImageDataURIFromBase64() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .file(mediaType: "image/jpeg", data: .base64("aGVsbG8="), providerOptions: nil),
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["image"] == .object(["url": "data:image/jpeg;base64,aGVsbG8="]))
    }

    @Test("sends video object to /videos/edits for video editing")
    func editModeSendsVideoObjectAndUsesEditsEndpoint() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createEditsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let providerOptions: SharedV3ProviderOptions = [
            "xai": [
                "videoUrl": "https://example.com/source-video.mp4",
                "pollIntervalMs": 10,
                "pollTimeoutMs": 5_000,
            ]
        ]

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: providerOptions
        ))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(call.url == createEditsURL)
        #expect(body["video"] == .object(["url": "https://example.com/source-video.mp4"]))
    }

    @Test("warns about duration/aspectRatio/resolution in edit mode and omits them from body")
    func editModeWarningsAndOmissions() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createEditsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let providerOptions: SharedV3ProviderOptions = [
            "xai": [
                "videoUrl": "https://example.com/source-video.mp4",
                "pollIntervalMs": 10,
                "pollTimeoutMs": 5_000,
            ]
        ]

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            aspectRatio: "16:9",
            resolution: "1280x720",
            duration: 10,
            providerOptions: providerOptions
        ))

        #expect(result.warnings.contains(where: { if case .unsupported(feature: "duration", details: _) = $0 { true } else { false } }))
        #expect(result.warnings.contains(where: { if case .unsupported(feature: "aspectRatio", details: _) = $0 { true } else { false } }))
        #expect(result.warnings.contains(where: { if case .unsupported(feature: "resolution", details: _) = $0 { true } else { false } }))

        guard let call = await stub.call(at: 0), case let .object(body)? = call.body else {
            Issue.record("Missing body")
            return
        }

        #expect(body["duration"] == nil)
        #expect(body["aspect_ratio"] == nil)
        #expect(body["resolution"] == nil)
    }

    @Test("passes headers to requests (create + poll)")
    func headersAreCombined() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(
            headers: { ["Authorization": "Bearer custom-token", "X-Custom": "value"] },
            fetch: { request in try await stub.handle(request) }
        )

        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: defaultProviderOptions,
            headers: ["X-Request-Header": "request-value"]
        ))

        guard let createCall = await stub.call(at: 0) else {
            Issue.record("Missing create call")
            return
        }
        guard let pollCall = await stub.call(at: 1) else {
            Issue.record("Missing poll call")
            return
        }

        func header(_ headers: [String: String], _ key: String) -> String? {
            headers.first(where: { $0.key.lowercased() == key.lowercased() })?.value
        }

        #expect(header(createCall.headers, "authorization") == "Bearer custom-token")
        #expect(header(createCall.headers, "x-custom") == "value")
        #expect(header(createCall.headers, "x-request-header") == "request-value")

        #expect(header(pollCall.headers, "authorization") == "Bearer custom-token")
        #expect(header(pollCall.headers, "x-custom") == "value")
        #expect(header(pollCall.headers, "x-request-header") == "request-value")
    }

    @Test("returns video with correct URL and media type")
    func returnsVideoURL() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.videos == [
            .url(url: "https://vidgen.x.ai/output/video-001.mp4", mediaType: "video/mp4")
        ])
    }

    @Test("handles done response without status field")
    func doneWithoutStatusField() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: [
            "video": [
                "url": "https://vidgen.x.ai/output/video-001.mp4",
                "duration": 5,
                "respect_moderation": true,
            ],
            "model": "grok-imagine-video",
        ])

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.videos.count == 1)
    }

    @Test("returns empty warnings for supported features")
    func emptyWarningsForDefaults() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.warnings.isEmpty)
    }

    @Test("warns about unsupported fps")
    func warnsUnsupportedFPS() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            fps: 30,
            providerOptions: defaultProviderOptions
        ))

        #expect(result.warnings.contains(where: { if case .unsupported(feature: "fps", details: _) = $0 { true } else { false } }))
    }

    @Test("warns about unsupported seed")
    func warnsUnsupportedSeed() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            seed: 42,
            providerOptions: defaultProviderOptions
        ))

        #expect(result.warnings.contains(where: { if case .unsupported(feature: "seed", details: _) = $0 { true } else { false } }))
    }

    @Test("warns when n > 1 and does not warn when n == 1")
    func warnsWhenNGreaterThan1() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 3,
            providerOptions: defaultProviderOptions
        ))

        #expect(result.warnings.contains(where: { if case .unsupported(feature: "n", details: _) = $0 { true } else { false } }))

        // n == 1 should not warn
        let result2 = try await model.doGenerate(options: defaultOptions)
        #expect(!result2.warnings.contains(where: { if case .unsupported(feature: "n", details: _) = $0 { true } else { false } }))
    }

    @Test("response includes timestamp, headers, and modelId")
    func responseMetadata() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let testDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
        let model = makeModel(
            fetch: { request in try await stub.handle(request) },
            currentDate: { testDate }
        )

        let result = try await model.doGenerate(options: defaultOptions)
        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "grok-imagine-video")
        #expect(result.response.headers != nil)
    }

    @Test("providerMetadata includes requestId, videoUrl, and duration")
    func providerMetadata() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })
        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.providerMetadata == [
            "xai": [
                "requestId": "req-123",
                "videoUrl": "https://vidgen.x.ai/output/video-001.mp4",
                "duration": 5,
            ]
        ])
    }

    @Test("throws when status is expired")
    func errorExpired() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: [
            "status": "expired",
            "model": "grok-imagine-video",
        ])

        let model = makeModel(fetch: { request in try await stub.handle(request) })

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("expired"))
        }
    }

    @Test("throws when no request_id is returned")
    func errorMissingRequestId() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: [:])
        try await stub.setJSON(method: "GET", url: statusURL, body: doneStatusResponse)

        let model = makeModel(fetch: { request in try await stub.handle(request) })

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("No request_id"))
        }
    }

    @Test("throws when video URL is missing on done status")
    func errorMissingVideoURLOnDone() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: [
            "status": "done",
            "video": NSNull(),
            "model": "grok-imagine-video",
        ])

        let model = makeModel(fetch: { request in try await stub.handle(request) })

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("no video url"))
        }
    }

    @Test("throws on timeout")
    func errorTimeout() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createGenerationsURL, body: createVideoResponse)
        try await stub.setJSON(method: "GET", url: statusURL, body: [
            "status": "pending",
            "model": "grok-imagine-video",
        ])

        let providerOptions: SharedV3ProviderOptions = [
            "xai": [
                "pollIntervalMs": 10,
                "pollTimeoutMs": 50,
            ]
        ]

        let model = makeModel(fetch: { request in try await stub.handle(request) })

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: providerOptions
            ))
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("timed out"))
        }
    }
}
