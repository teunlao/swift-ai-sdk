import Foundation
import Testing
@testable import ReplicateProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils

private let prompt = "The Loch Ness monster getting a manicure"

@Suite("ReplicateImageModel")
struct ReplicateImageModelTests {
    @Test("passes model settings and providerOptions, builds body")
    func passesModelAndSettings() async throws {
        // Capture the first POST request body
        actor Capture {
            var request: URLRequest?
            func store(_ req: URLRequest) { request = req }
            func value() -> URLRequest? { request }
        }
        let cap = Capture()

        // Mock binary download response
        let binary = Data("test-binary-content".utf8)

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if request.httpMethod == "POST" && url.contains("/v1/") {
                await cap.store(request)
                // JSON response with output array
                let body: [String: Any] = [
                    "id": "s7x1e3dcmhrmc0cm8rbatcneec",
                    "model": "black-forest-labs/flux-schnell",
                    "version": "dp-4d0bcc010b3049749a251855f12800be",
                    "input": ["num_outputs": 1, "prompt": prompt],
                    "output": ["https://replicate.delivery/xezq/abc/out-0.webp"],
                    "status": "processing"
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else if request.httpMethod == "GET" && url.contains("replicate.delivery") {
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "image/webp"]
                )!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return FetchResponse(body: .data(Data()), urlResponse: resp)
        }

        // Build model via provider to include headers logic
        let provider = createReplicate(settings: ReplicateProviderSettings(
            apiToken: "test-api-token",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        let model = provider.image("black-forest-labs/flux-schnell")

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            size: "1024x768",
            aspectRatio: "3:4",
            seed: 123,
            providerOptions: [
                "replicate": ["style": .string("realistic_image")],
                "other": ["something": .string("else")]
            ],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await cap.value(),
              let data = request.httpBody else {
            Issue.record("Expected captured POST request with body")
            return
        }

        // Verify body JSON matches upstream semantics
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let input = json["input"] as? [String: Any] else {
            Issue.record("Missing input object in request body")
            return
        }
        #expect(input["prompt"] as? String == prompt)
        #expect(input["num_outputs"] as? Int == 1)
        #expect(input["aspect_ratio"] as? String == "3:4")
        #expect(input["size"] as? String == "1024x768")
        #expect(input["seed"] as? Int == 123)
        #expect(input["style"] as? String == "realistic_image")

        // Verify headers merged + prefer=wait
        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { r, p in r[p.key.lowercased()] = p.value }
        #expect(headers["content-type"] == "application/json")
        #expect(headers["authorization"] == "Bearer test-api-token")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["prefer"] == "wait")
    }

    @Test("should pass headers and set the prefer header")
    func passHeadersAndPreferHeader() async throws {
        actor Capture { var firstPost: URLRequest?; func store(_ r: URLRequest) { if firstPost == nil && r.httpMethod == "POST" { firstPost = r } }; func value() -> URLRequest? { firstPost } }
        let cap = Capture()

        let binary = Data([0xAA])
        let fetch: FetchFunction = { request in
            await cap.store(request)
            if request.httpMethod == "POST" {
                let body: [String: Any] = [
                    "output": ["https://replicate.delivery/xezq/abc/out-0.webp"]
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/webp"])!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
        }

        let provider = createReplicate(settings: ReplicateProviderSettings(
            apiToken: "test-api-token",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider.image("black-forest-labs/flux-schnell").doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await cap.value() else {
            Issue.record("Expected captured request")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { r, p in r[p.key.lowercased()] = p.value }
        #expect(headers["authorization"] == "Bearer test-api-token")
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["prefer"] == "wait")
    }

    @Test("should call the correct url")
    func callCorrectURL() async throws {
        actor Calls { var list: [URLRequest] = []; func add(_ r: URLRequest) { list.append(r) }; func all() -> [URLRequest] { list } }
        let calls = Calls()
        let binary = Data([0xAB])
        let fetch: FetchFunction = { request in
            await calls.add(request)
            if request.httpMethod == "POST" {
                let body: [String: Any] = [
                    "output": ["https://replicate.delivery/xezq/abc/out-0.webp"]
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/webp"])!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
        }

        let model = ReplicateImageModel(
            "black-forest-labs/flux-schnell",
            config: ReplicateImageModelConfig(
                provider: "replicate",
                baseURL: "https://api.replicate.com/v1",
                headers: { [:] },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        let list = await calls.all()
        #expect(list.first?.httpMethod == "POST")
        #expect(list.first?.url?.absoluteString == "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")
    }

    @Test("should extract the generated image from string response")
    func extractStringResponseImage() async throws {
        actor Calls { var list: [URLRequest] = []; func add(_ r: URLRequest) { list.append(r) }; func all() -> [URLRequest] { list } }
        let calls = Calls()
        let binary = Data("test-binary-content".utf8)
        let fetch: FetchFunction = { request in
            await calls.add(request)
            if request.httpMethod == "POST" {
                let body: [String: Any] = [
                    "output": "https://replicate.delivery/xezq/abc/out-0.webp"
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/webp"])!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
        }

        let model = ReplicateImageModel(
            "black-forest-labs/flux-schnell",
            config: ReplicateImageModelConfig(
                provider: "replicate",
                baseURL: "https://api.replicate.com/v1",
                headers: { [:] },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        if case let .binary(images) = result.images {
            #expect(images == [binary])
        } else {
            Issue.record("Expected binary images from string response")
        }

        let list = await calls.all()
        #expect(list.count == 2)
        #expect(list[1].httpMethod == "GET")
        #expect(list[1].url?.absoluteString == "https://replicate.delivery/xezq/abc/out-0.webp")
    }

    @Test("should return response metadata")
    func returnResponseMetadata() async throws {
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        let binary = Data([0x01])
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST" {
                let body: [String: Any] = [
                    "output": ["https://replicate.delivery/xezq/abc/out-0.webp"]
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/webp"])!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
        }

        let model = ReplicateImageModel(
            "black-forest-labs/flux-schnell",
            config: ReplicateImageModelConfig(
                provider: "replicate",
                baseURL: "https://api.replicate.com/v1",
                headers: { [:] },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "black-forest-labs/flux-schnell")
    }

    @Test("calls correct URL for unversioned model and downloads image (array response)")
    func urlUnversionedAndDownloadArray() async throws {
        // Two-step fetch: POST -> GET
        actor CallStore1 { var items: [URLRequest] = []; func add(_ r: URLRequest) { items.append(r) }; func all() -> [URLRequest] { items } }
        let callsStore1 = CallStore1()
        let binary = Data("test-binary-content".utf8)
        let fetch: FetchFunction = { request in
            await callsStore1.add(request)
            if request.httpMethod == "POST" {
                let body: [String: Any] = [
                    "output": ["https://replicate.delivery/xezq/abc/out-0.webp"]
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/webp"])!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
        }

        let model = ReplicateImageModel(
            "black-forest-labs/flux-schnell",
            config: ReplicateImageModelConfig(
                provider: "replicate",
                baseURL: "https://api.replicate.com/v1",
                headers: { ["Authorization": "Bearer test-api-token"] },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        // Verify URL for POST
        let calls = await callsStore1.all()
        #expect(calls.first?.httpMethod == "POST")
        #expect(calls.first?.url?.absoluteString == "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")
        // Verify GET to delivery
        #expect(calls.count == 2)
        #expect(calls[1].httpMethod == "GET")
        #expect(calls[1].url?.absoluteString == "https://replicate.delivery/xezq/abc/out-0.webp")

        if case let .binary(images) = result.images {
            #expect(images == [binary])
        } else {
            Issue.record("Expected binary images")
        }
    }

    @Test("string output handled and versioned model uses /predictions with version in body")
    func stringOutputAndVersionedModel() async throws {
        actor CallStore2 { var items: [URLRequest] = []; func add(_ r: URLRequest) { items.append(r) }; func all() -> [URLRequest] { items } }
        let callsStore2 = CallStore2()
        let binary = Data("test-binary-content".utf8)
        let fetch: FetchFunction = { request in
            await callsStore2.add(request)
            if request.httpMethod == "POST" {
                let body: [String: Any] = [
                    "output": "https://replicate.delivery/xezq/abc/out-0.webp"
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/webp"])!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
        }

        let model = ReplicateImageModel(
            "bytedance/sdxl-lightning-4step:5599ed30703defd1d160a25a63321b4dec97101d98b4674bcc56e41f62f35637",
            config: ReplicateImageModelConfig(
                provider: "replicate",
                baseURL: "https://api.replicate.com/v1",
                headers: { [:] },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        // Verify POST URL and body has version
        let calls = await callsStore2.all()
        #expect(calls.first?.url?.absoluteString == "https://api.replicate.com/v1/predictions")
        if let body = calls.first?.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["version"] as? String == "5599ed30703defd1d160a25a63321b4dec97101d98b4674bcc56e41f62f35637")
        } else {
            Issue.record("Expected request body with version")
        }
    }

    @Test("returns response metadata with headers")
    func returnsResponseMetadataWithHeaders() async throws {
        let testDate = Date(timeIntervalSince1970: 1_704_000_000)
        actor CallStore3 { var items: [URLRequest] = []; func add(_ r: URLRequest) { items.append(r) }; func all() -> [URLRequest] { items } }
        let callsStore3 = CallStore3()
        let binary = Data([0x01])
        let fetch: FetchFunction = { request in
            await callsStore3.add(request)
            if request.httpMethod == "POST" {
                let body: [String: Any] = [
                    "output": ["https://replicate.delivery/xezq/abc/out-0.webp"]
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/json",
                        "custom-response-header": "response-header-value"
                    ]
                )!
                return FetchResponse(body: .data(data), urlResponse: resp)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/webp"])!
                return FetchResponse(body: .data(binary), urlResponse: resp)
            }
        }

        let model = ReplicateImageModel(
            "black-forest-labs/flux-schnell",
            config: ReplicateImageModelConfig(
                provider: "replicate",
                baseURL: "https://api.replicate.com/v1",
                headers: { [:] },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        #expect(result.response.modelId == "black-forest-labs/flux-schnell")
        #expect(result.response.timestamp == testDate)
        let headers = result.response.headers ?? [:]
        #expect(headers["custom-response-header"] == "response-header-value")
        #expect(headers["content-type"] == "application/json")
    }
}
