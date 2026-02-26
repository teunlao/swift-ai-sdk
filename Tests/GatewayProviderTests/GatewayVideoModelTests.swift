import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayVideoModel")
struct GatewayVideoModelTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            if key == "user-agent" { return }
            result[key] = pair.value
        }
    }

    private func httpResponse(for request: URLRequest, statusCode: Int = 200, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func sseData(_ payload: String) -> Data {
        Data(("data: \(payload)\n\n").utf8)
    }

    private func makeModel(
        modelId: GatewayVideoModelId = GatewayVideoModelId(rawValue: "google/veo-3.1-generate-001"),
        fetch: @escaping FetchFunction,
        o11yHeaders: [String: String] = [:],
        provider: String = "gateway"
    ) -> GatewayVideoModel {
        GatewayVideoModel(
            modelId: modelId,
            config: GatewayVideoModelConfig(
                provider: provider,
                baseURL: "https://api.test.com",
                headers: { () async throws -> [String: String?] in
                    [
                        "Authorization": "Bearer test-token",
                        GATEWAY_AUTH_METHOD_HEADER: "api-key",
                    ]
                },
                fetch: fetch,
                o11yHeaders: { () async throws -> [String: String?] in
                    o11yHeaders.mapValues { Optional($0) }
                }
            )
        )
    }

    @Test("constructor exposes modelId/provider/specVersion and avoids client-side splitting")
    func constructorProperties() async throws {
        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(sseData(#"{"type":"result","videos":[{"type":"base64","data":"ok","mediaType":"video/mp4"}]}"#)), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        #expect(model.modelId == "google/veo-3.1-generate-001")
        #expect(model.provider == "gateway")
        #expect(model.specificationVersion == "v3")

        guard case .value(let max) = model.maxVideosPerCall else {
            Issue.record("Expected fixed maxVideosPerCall")
            return
        }
        #expect(max == Int.max)

        let customProvider = makeModel(fetch: fetch, provider: "custom-gateway")
        #expect(customProvider.provider == "custom-gateway")
    }

    @Test("doGenerate sends correct headers/body and maps videos + providerMetadata")
    func doGenerateHeadersBodyAndResponseMapping() async throws {
        let capture = RequestCapture()

        let event = #"{"type":"result","videos":[{"type":"base64","data":"base64-video-1","mediaType":"video/mp4"},{"type":"url","url":"https://example.com/video.mp4","mediaType":"video/mp4"}],"providerMetadata":{"gateway":{"routing":{"provider":"fal"},"cost":"0.15"}}}"#
        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream", "X-Test": "1"])
            return FetchResponse(body: .data(sseData(event)), urlResponse: httpResponse)
        }

        let o11yHeaders: [String: String] = [
            "ai-o11y-deployment-id": "dpl_123",
            "ai-o11y-environment": "production",
        ]

        let model = makeModel(fetch: fetch, o11yHeaders: o11yHeaders)
        let result = try await model.doGenerate(options: .init(
            prompt: "A cat playing piano",
            n: 1,
            aspectRatio: "16:9",
            resolution: "1920x1080",
            duration: 5,
            fps: 24,
            seed: 42,
            providerOptions: ["fal": ["motionStrength": .number(0.8)]],
            headers: ["X-Custom-Header": "custom-value"]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.test.com/video-model")

        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer test-token")
        #expect(headers["x-custom-header"] == "custom-value")
        #expect(headers["ai-video-model-specification-version"] == "3")
        #expect(headers["ai-model-id"] == "google/veo-3.1-generate-001")
        #expect(headers["accept"] == "text/event-stream")
        for (key, value) in o11yHeaders {
            #expect(headers[key] == value)
        }

        #expect(json["prompt"] as? String == "A cat playing piano")
        #expect((json["n"] as? Double) == 1 || (json["n"] as? Int) == 1)
        #expect(json["aspectRatio"] as? String == "16:9")
        #expect(json["resolution"] as? String == "1920x1080")
        #expect((json["duration"] as? Double) == 5 || (json["duration"] as? Int) == 5)
        #expect((json["fps"] as? Double) == 24 || (json["fps"] as? Int) == 24)
        #expect((json["seed"] as? Double) == 42 || (json["seed"] as? Int) == 42)

        guard let providerOptions = json["providerOptions"] as? [String: Any],
              let fal = providerOptions["fal"] as? [String: Any]
        else {
            Issue.record("Expected providerOptions.fal")
            return
        }
        #expect((fal["motionStrength"] as? Double) == 0.8)

        #expect(result.videos == [
            .base64(data: "base64-video-1", mediaType: "video/mp4"),
            .url(url: "https://example.com/video.mp4", mediaType: "video/mp4"),
        ])

        #expect(result.warnings == [])
        #expect(result.response.modelId == "google/veo-3.1-generate-001")
        #expect(result.response.headers?["content-type"] == "text/event-stream")
        #expect(result.response.headers?["x-test"] == "1")

        #expect(result.providerMetadata?["gateway"]?["cost"] == .string("0.15"))
    }

    @Test("doGenerate omits optional parameters when not provided (but includes empty providerOptions)")
    func doGenerateOmitsOptionalParameters() async throws {
        let capture = RequestCapture()

        let event = #"{"type":"result","videos":[{"type":"base64","data":"ok","mediaType":"video/mp4"}]}"#
        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(sseData(event)), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: "A simple prompt",
            n: 1,
            providerOptions: [:]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["prompt"] as? String == "A simple prompt")
        #expect((json["n"] as? Double) == 1 || (json["n"] as? Int) == 1)
        #expect(json["providerOptions"] != nil)

        #expect(json["aspectRatio"] == nil)
        #expect(json["resolution"] == nil)
        #expect(json["duration"] == nil)
        #expect(json["fps"] == nil)
        #expect(json["seed"] == nil)
        #expect(json["image"] == nil)
    }

    @Test("doGenerate throws on SSE error event and maps to Gateway errors")
    func doGenerateSSEErrorEventMapping() async throws {
        let rateLimitEvent = #"{"type":"error","message":"Rate limit exceeded","errorType":"rate_limit_exceeded","statusCode":429,"param":null}"#
        let fetchRateLimit: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(sseData(rateLimitEvent)), urlResponse: httpResponse)
        }

        do {
            let model = makeModel(fetch: fetchRateLimit)
            _ = try await model.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))
            Issue.record("Expected error")
        } catch {
            #expect(GatewayRateLimitError.isInstance(error))
            if let err = error as? GatewayRateLimitError {
                #expect(err.statusCode == 429)
                #expect(err.message == "Rate limit exceeded")
            }
        }

        let internalEvent = #"{"type":"error","message":"All providers failed","errorType":"internal_server_error","statusCode":500,"param":null}"#
        let fetchInternal: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(sseData(internalEvent)), urlResponse: httpResponse)
        }

        do {
            let model = makeModel(fetch: fetchInternal)
            _ = try await model.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))
            Issue.record("Expected error")
        } catch {
            #expect(GatewayInternalServerError.isInstance(error))
            if let err = error as? GatewayInternalServerError {
                #expect(err.statusCode == 500)
                #expect(err.message == "All providers failed")
            }
        }
    }

    @Test("doGenerate throws on empty SSE stream")
    func doGenerateEmptySSEStream() async throws {
        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(Data()), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        await #expect(throws: GatewayResponseError.self) {
            _ = try await model.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))
        }
    }

    @Test("doGenerate ignores SSE heartbeat comments and parses the first data event")
    func doGenerateIgnoresHeartbeatComments() async throws {
        let capture = RequestCapture()

        let chunks: [String] = [
            ":\n\n",
            ":\n\n",
            "data: {\"type\":\"result\",\"videos\":[{\"type\":\"base64\",\"data\":\"base64-1\",\"mediaType\":\"video/mp4\"}]}\n\n",
        ]
        let data = Data(chunks.joined().utf8)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))
        #expect(result.videos == [.base64(data: "base64-1", mediaType: "video/mp4")])
    }

    @Test("doGenerate encodes image-to-video file inputs as base64 strings and preserves providerOptions")
    func doGenerateEncodesImageFile() async throws {
        let capture = RequestCapture()

        let event = #"{"type":"result","videos":[{"type":"base64","data":"ok","mediaType":"video/mp4"}]}"#
        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(sseData(event)), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let binary = Data([72, 101, 108, 108, 111]) // "Hello"
        let expectedBase64 = binary.base64EncodedString()

        _ = try await model.doGenerate(options: .init(
            prompt: "Animate this image",
            n: 1,
            image: .file(
                mediaType: "image/png",
                data: .binary(binary),
                providerOptions: ["fal": ["enhanceImage": .bool(true)]]
            ),
            providerOptions: [:]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let image = json["image"] as? [String: Any]
        else {
            Issue.record("Expected image in request body")
            return
        }

        #expect(image["type"] as? String == "file")
        #expect(image["mediaType"] as? String == "image/png")
        #expect(image["data"] as? String == expectedBase64)

        guard let providerOptions = image["providerOptions"] as? [String: Any],
              let fal = providerOptions["fal"] as? [String: Any]
        else {
            Issue.record("Expected image.providerOptions.fal")
            return
        }
        #expect(fal["enhanceImage"] as? Bool == true)

        // Pass-through url + already-base64 values
        _ = try await model.doGenerate(options: .init(
            prompt: "Animate this image",
            n: 1,
            image: .file(mediaType: "image/png", data: .base64("already-base64-encoded"), providerOptions: nil),
            providerOptions: [:]
        ))

        guard let request2 = await capture.current(),
              let body2 = request2.httpBody,
              let json2 = try JSONSerialization.jsonObject(with: body2) as? [String: Any],
              let image2 = json2["image"] as? [String: Any]
        else {
            Issue.record("Expected second image in request body")
            return
        }
        #expect(image2["data"] as? String == "already-base64-encoded")

        _ = try await model.doGenerate(options: .init(
            prompt: "Animate this image",
            n: 1,
            image: .url(url: "https://example.com/image.png", providerOptions: nil),
            providerOptions: [:]
        ))

        guard let request3 = await capture.current(),
              let body3 = request3.httpBody,
              let json3 = try JSONSerialization.jsonObject(with: body3) as? [String: Any],
              let image3 = json3["image"] as? [String: Any]
        else {
            Issue.record("Expected third image in request body")
            return
        }
        #expect(image3["type"] as? String == "url")
        #expect(image3["url"] as? String == "https://example.com/image.png")
    }

    @Test("doGenerate includes providerOptions object (including empty) in the request body")
    func doGenerateProviderOptionsMapping() async throws {
        let capture = RequestCapture()

        let event = #"{"type":"result","videos":[{"type":"base64","data":"ok","mediaType":"video/mp4"}]}"#
        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(sseData(event)), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: "Test",
            n: 1,
            providerOptions: [
                "fal": [
                    "motionStrength": .number(0.8),
                    "loop": .bool(true),
                ],
                "google": [
                    "enhancePrompt": .bool(true),
                ],
            ]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let providerOptions = json["providerOptions"] as? [String: Any]
        else {
            Issue.record("Expected providerOptions in request body")
            return
        }

        #expect(providerOptions["fal"] != nil)
        #expect(providerOptions["google"] != nil)

        _ = try await model.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))
        guard let request2 = await capture.current(),
              let body2 = request2.httpBody,
              let json2 = try JSONSerialization.jsonObject(with: body2) as? [String: Any]
        else {
            Issue.record("Expected second request body")
            return
        }
        #expect(json2["providerOptions"] != nil)
    }
}
