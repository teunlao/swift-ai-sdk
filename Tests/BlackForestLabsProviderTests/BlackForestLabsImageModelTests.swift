import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import BlackForestLabsProvider

@Suite("BlackForestLabsImageModel")
struct BlackForestLabsImageModelTests {
    private func lowercasedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    private func decodeJSONBody(_ request: URLRequest) throws -> [String: Any] {
        guard let body = request.httpBody else { return [:] }
        return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
    }

    private func makeModel(
        modelId: BlackForestLabsImageModelId = "test-model",
        pollIntervalMillis: Int? = nil,
        pollTimeoutMillis: Int? = nil,
        headers: (@Sendable () -> [String: String?])? = { ["x-key": "test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> BlackForestLabsImageModel {
        BlackForestLabsImageModel(
            modelId: modelId,
            config: BlackForestLabsImageModelConfig(
                provider: "black-forest-labs.image",
                baseURL: "https://api.example.com/v1",
                headers: headers,
                fetch: fetch,
                pollIntervalMillis: pollIntervalMillis,
                pollTimeoutMillis: pollTimeoutMillis,
                currentDate: currentDate
            )
        )
    }

    @Test("passes correct parameters including aspect ratio and providerOptions")
    func passesParameters() async throws {
        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func all() -> [URLRequest] { calls }
        }

        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "image/png"]
                )!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: nil,
                aspectRatio: "16:9",
                seed: nil,
                providerOptions: [
                    "blackForestLabs": [
                        "promptUpsampling": .bool(true),
                        "unsupportedProperty": .string("value"),
                    ]
                ]
            )
        )

        let calls = await capture.all()
        guard let first = calls.first,
              let body = first.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing submit request capture")
            return
        }

        #expect(first.url?.absoluteString == "https://api.example.com/v1/test-model")
        #expect(json["prompt"] as? String == "A cute baby sea otter")
        #expect(json["aspect_ratio"] as? String == "16:9")
        #expect(json["prompt_upsampling"] as? Bool == true)
        #expect(json["unsupportedProperty"] == nil)
    }

    @Test("passes webhookSecret and webhookUrl provider options")
    func passesWebhookProviderOptions() async throws {
        actor Capture {
            var submitRequest: URLRequest?
            func storeSubmit(_ request: URLRequest) { self.submitRequest = request }
            func submit() -> URLRequest? { submitRequest }
        }

        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                await capture.storeSubmit(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "p",
            n: 1,
            providerOptions: [
                "blackForestLabs": [
                    "webhookSecret": .string("secret"),
                    "webhookUrl": .string("https://example.com/hook"),
                ]
            ]
        ))

        guard let request = await capture.submit() else {
            Issue.record("Missing captured submit request")
            return
        }

        let json = try decodeJSONBody(request)
        #expect(json["webhook_secret"] as? String == "secret")
        #expect(json["webhook_url"] as? String == "https://example.com/hook")
    }

    @Test("calls the expected URLs in sequence")
    func callsExpectedUrlsInSequence() async throws {
        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func all() -> [URLRequest] { calls }
        }

        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "p",
            n: 1,
            aspectRatio: "16:9",
            providerOptions: [:]
        ))

        let calls = await capture.all()
        #expect(calls.count == 3)
        #expect(calls[0].httpMethod == "POST")
        #expect(calls[0].url?.absoluteString == "https://api.example.com/v1/test-model")
        #expect(calls[1].httpMethod == "GET")
        #expect(calls[1].url?.absoluteString == "https://api.example.com/poll?id=req-123")
        #expect(calls[2].httpMethod == "GET")
        #expect(calls[2].url?.absoluteString == "https://api.example.com/image.png")
    }

    @Test("merges provider and request headers for submit call")
    func mergesHeadersForSubmitCall() async throws {
        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func all() -> [URLRequest] { calls }
        }

        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(headers: {
            [
                "Custom-Provider-Header": "provider-header-value",
                "x-key": "test-key",
            ]
        }, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "p",
            n: 1,
            providerOptions: [:],
            headers: [
                "Custom-Request-Header": "request-header-value"
            ]
        ))

        guard let submit = await capture.all().first else {
            Issue.record("Missing submit request capture")
            return
        }

        let headers = lowercasedHeaders(submit)
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["x-key"] == "test-key")
    }

    @Test("passes merged headers to polling requests")
    func passesMergedHeadersToPollingRequests() async throws {
        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func all() -> [URLRequest] { calls }
        }

        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(headers: {
            [
                "Custom-Provider-Header": "provider-header-value",
                "x-key": "test-key",
            ]
        }, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "p",
            n: 1,
            providerOptions: [:],
            headers: [
                "Custom-Request-Header": "request-header-value"
            ]
        ))

        let calls = await capture.all()
        guard calls.count >= 2 else {
            Issue.record("Expected at least poll call")
            return
        }

        let pollCall = calls[1]
        let headers = lowercasedHeaders(pollCall)
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["x-key"] == "test-key")
    }

    @Test("warns when size is provided and aspectRatio is also set")
    func warnsWhenSizeAndAspectRatioProvided() async throws {
        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(
            prompt: "p",
            n: 1,
            size: "1920x1080",
            aspectRatio: "16:9",
            providerOptions: [:]
        ))

        #expect(result.warnings == [
            .unsupported(
                feature: "size",
                details: "Black Forest Labs ignores size when aspectRatio is provided. Use the width and height provider options to specify dimensions for models that support them"
            )
        ])
    }

    @Test("handles API errors with message and detail")
    func handlesAPIErrorsMessageAndDetail() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: [
            "message": "Top-level message",
            "detail": ["error": "Invalid prompt"],
        ])

        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1/test-model")!,
            statusCode: 400,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                return FetchResponse(body: .data(responseData), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.message == "{\"error\":\"Invalid prompt\"}")
            #expect(error.statusCode == 400)
            #expect(error.url == "https://api.example.com/v1/test-model")
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }

    @Test("handles poll responses with state instead of status")
    func handlesStateInsteadOfStatus() async throws {
        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "state": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: "p", n: 1, aspectRatio: "1:1", providerOptions: [:]))

        switch result.images {
        case .binary(let images):
            #expect(images.count == 1)
        default:
            Issue.record("Expected binary images")
        }
    }

    @Test("polls multiple times until Ready using configured interval")
    func pollsMultipleTimesUntilReady() async throws {
        actor Counter {
            var value: Int = 0
            func next() -> Int {
                value += 1
                return value
            }
        }

        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func all() -> [URLRequest] { calls }
        }

        let counter = Counter()
        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let callNumber = await counter.next()
                let body: [String: Any]
                if callNumber < 3 {
                    body = ["status": "Pending"]
                } else {
                    body = ["status": "Ready", "result": ["sample": "https://api.example.com/image.png"]]
                }
                let pollData = try JSONSerialization.data(withJSONObject: body)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(pollIntervalMillis: 1, pollTimeoutMillis: 1000, fetch: fetch)

        _ = try await model.doGenerate(options: .init(prompt: "p", n: 1, aspectRatio: "1:1", providerOptions: [:]))

        let calls = await capture.all()
        let pollCalls = calls.filter { $0.httpMethod == "GET" && ($0.url?.absoluteString.hasPrefix("https://api.example.com/poll") == true) }
        #expect(pollCalls.count == 3)
    }

    @Test("uses configured pollTimeoutMillis and pollIntervalMillis to time out")
    func timesOutWithConfiguredPolling() async throws {
        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func all() -> [URLRequest] { calls }
        }

        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let pollData = try JSONSerialization.data(withJSONObject: ["status": "Pending"])
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let pollIntervalMillis = 10
        let pollTimeoutMillis = 25
        let model = makeModel(pollIntervalMillis: pollIntervalMillis, pollTimeoutMillis: pollTimeoutMillis, fetch: fetch)

        await #expect(throws: InvalidResponseDataError.self) {
            _ = try await model.doGenerate(options: .init(prompt: "p", n: 1, aspectRatio: "1:1", providerOptions: [:]))
        }

        let calls = await capture.all()
        let pollCalls = calls.filter { $0.httpMethod == "GET" && ($0.url?.absoluteString.hasPrefix("https://api.example.com/poll") == true) }
        #expect(pollCalls.count == Int(ceil(Double(pollTimeoutMillis) / Double(pollIntervalMillis))))

        let imageCalls = calls.filter { $0.url?.absoluteString.hasPrefix("https://api.example.com/image.png") == true }
        #expect(imageCalls.count == 0)
    }

    @Test("throws when poll returns Error or Failed")
    func throwsWhenPollReturnsErrorOrFailed() async throws {
        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Error",
        ])

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        await #expect(throws: InvalidResponseDataError.self) {
            _ = try await model.doGenerate(options: .init(prompt: "p", n: 1, aspectRatio: "1:1", providerOptions: [:]))
        }
    }

    @Test("warns and derives aspect_ratio when size is provided")
    func warnsAndDerivesAspectRatioFromSize() async throws {
        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        actor Capture {
            var aspectRatio: String?
            func store(aspectRatio: String?) { self.aspectRatio = aspectRatio }
            func currentAspectRatio() -> String? { aspectRatio }
        }
        let capture = Capture()

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                if let body = request.httpBody,
                   let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    await capture.store(aspectRatio: json["aspect_ratio"] as? String)
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "image/png"]
                )!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }
            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "p",
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:]
            )
        )

        #expect(result.warnings == [
            SharedV3Warning.unsupported(
                feature: "size",
                details: "Deriving aspect_ratio from size. Use the width and height provider options to specify dimensions for models that support them."
            )
        ])

        #expect(await capture.currentAspectRatio() == "1:1")
    }

    @Test("throws when poll is Ready but sample is missing")
    func throwsWhenReadyMissingSample() async throws {
        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": NSNull(),
        ])

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        await #expect(throws: InvalidResponseDataError.self) {
            _ = try await model.doGenerate(
                options: ImageModelV3CallOptions(
                    prompt: "p",
                    n: 1,
                    size: nil,
                    aspectRatio: "1:1",
                    seed: nil,
                    providerOptions: [:]
                )
            )
        }
    }

    @Test("exposes correct provider and model information")
    func constructorMetadata() throws {
        let model = makeModel()
        #expect(model.provider == "black-forest-labs.image")
        #expect(model.modelId == "test-model")
        #expect(model.specificationVersion == "v3")
    }
}
