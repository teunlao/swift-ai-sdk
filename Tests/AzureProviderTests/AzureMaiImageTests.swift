import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

private final class MaiFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private actor MaiRequests {
    var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
    func all() -> [URLRequest] { requests }
}

private func maiResponse(_ request: URLRequest, body: String = #"{"data":[{"b64_json":"image"}]}"#, status: Int = 200) -> FetchResponse {
    FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json", "X-Request-Id": "mai-request"]
    )!)
}

@Suite("Azure MAI image")
struct AzureMaiImageTests {
    @Test("MAI generation uses its API, dimensions, options and aggregate usage")
    func generation() async throws {
        let requests = MaiRequests()
        let provider = try createAzure(settings: .init(
            resourceName: "image-resource", apiKey: "image-key",
            headers: ["X-Image-Header": "configured"], fetch: { request in
                await requests.append(request)
                return maiResponse(request, body: #"{"created":1234.5,"size":"1360x768","usage":{"num_input_text_tokens":10,"num_input_image_tokens":0,"num_output_tokens":576},"data":[{"b64_json":"image"}],"future":true}"#)
            }
        ))
        let model: any ImageModelV4 = provider.image("MAI-Image-2.6-Flash")
        let before = Date()
        let result = try await model.doGenerate(options: .init(
            prompt: "Нарисуй яблоко", n: 2, aspectRatio: "16:9", seed: 42,
            providerOptions: ["azure": ["autoAspectRatio": true, "webGrounding": false]],
            headers: ["X-Image-Header": "caller"]
        ))
        for request in await requests.all() {
            #expect(request.url?.absoluteString == "https://image-resource.services.ai.azure.com/mai/v1/images/generations")
            #expect(request.value(forHTTPHeaderField: "api-key") == "image-key")
            #expect(request.value(forHTTPHeaderField: "X-Image-Header") == "caller")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-azure/") == true)
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object(["model": "MAI-Image-2.6-Flash", "prompt": "Нарисуй яблоко",
                "width": 1360, "height": 768, "auto_aspect_ratio": true, "web_grounding": false]))
        }
        #expect(result.images == .base64(["image", "image"]))
        #expect(result.usage == .init(inputTokens: 20, outputTokens: 1152, totalTokens: 1172))
        #expect(result.warnings == [.unsupported(feature: "seed", details: nil)])
        #expect(result.response.timestamp >= before && result.response.timestamp <= Date())
        #expect(result.response.modelId == "MAI-Image-2.6-Flash")
        #expect(result.response.headers?["x-request-id"] == "mai-request")
        #expect(result.providerMetadata?["azure"]?.images == [
            .object(["created": 1234.5, "size": "1360x768", "textTokens": 10, "imageTokens": 0]),
            .object(["created": 1234.5, "size": "1360x768", "textTokens": 10, "imageTokens": 0])
        ])
        #expect(try await model.supportsFileInputs == true)
        #expect(try await model.supportsMaskInputs == false)
        guard case .value(let capacity) = model.maxImagesPerCall else { Issue.record("Missing capacity"); return }
        #expect(capacity == 1)
    }

    @Test("Image API selection is per request while capabilities follow model defaults", arguments: [
        ("MAI-Image-2.5", true), ("mai-image-2.5-flash", true), ("MAI-Image-2.5-Pro", true),
        ("mai-image-2.6", true), ("MAI-Image-2.6-FLASH", true), ("mai-image-custom", false), ("dall-e-3", false)
    ])
    func selection(_ id: String, _ mai: Bool) async throws {
        let provider = try createAzure(settings: .init(resourceName: "image-resource", apiKey: "key", fetch: { request in
            #expect(request.url?.host == "image-resource.\(mai ? "services.ai" : "openai").azure.com")
            return maiResponse(request)
        }))
        let api: any ProviderV4 = provider
        let model = try api.imageModel(modelId: id)
        #expect(try await model.supportsFileInputs == (mai ? true : nil))
        #expect(try await model.supportsMaskInputs == (mai ? false : nil))
        let result = try await model.doGenerate(options: .init(n: 0, files: nil,
            providerOptions: ["azure": ["someFutureOption": "ignored"]]))
        #expect(result.images == .base64(["image"]))
        #expect(result.usage == nil)
    }

    @Test("A deployment can select both APIs without changing advertised capabilities")
    func override() async throws {
        let requests = MaiRequests()
        let provider = try createAzure(settings: .init(baseURL: "https://proxy.example.com/openai/",
            maiBaseURL: "https://proxy.example.com/mai/v1/", tokenProvider: { "entra-image" },
            headers: ["X-Provider": "configured"], fetch: { request in
                await requests.append(request)
                return maiResponse(request)
            }))
        let model = provider.imageModel("custom-deployment")
        let maiOptions = AzureImageModelOptions(api: .mai, autoAspectRatio: false, webGrounding: true)
        let encoded = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(maiOptions))
        let mai = try await model.doGenerate(options: .init(n: 1, providerOptions: ["azure": encoded]))
        let openai = try await model.doGenerate(options: .init(n: 1,
            providerOptions: ["azure": ["api": "openai", "autoAspectRatio": false, "webGrounding": true],
                "openai": ["quality": "high"]], headers: ["Authorization": "Bearer caller"]))
        let all = await requests.all()
        #expect(all.map { $0.url?.absoluteString } == [
            "https://proxy.example.com/mai/v1/images/generations", "https://proxy.example.com/openai/images/generations"])
        #expect(all.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer entra-image", "Bearer caller"])
        #expect(all.allSatisfy { $0.value(forHTTPHeaderField: "api-key") == nil && $0.value(forHTTPHeaderField: "X-Provider") == "configured" })
        let bodies = try all.map { try JSONDecoder().decode(JSONValue.self, from: #require($0.httpBody)) }
        #expect(bodies == [
            .object(["model": "custom-deployment", "auto_aspect_ratio": false, "web_grounding": true]),
            .object(["model": "custom-deployment", "n": 1, "quality": "high", "response_format": "b64_json"])
        ])
        #expect(mai.images == .base64(["image"]))
        #expect(openai.warnings == [
            .unsupported(feature: "providerOptions.azure.autoAspectRatio", details: "This option requires the MAI image API."),
            .unsupported(feature: "providerOptions.azure.webGrounding", details: "This option requires the MAI image API.")
        ])
        #expect(try await model.supportsFileInputs == nil)
        #expect(try await model.supportsMaskInputs == nil)
    }

    @Test("MAI edits retain ordered image bytes and use repeated image fields without masks")
    func edits() async throws {
        let provider = try createAzure(settings: .init(resourceName: "image-resource", apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/mai/v1/images/edits")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
            #expect(body.contains("name=\"model\"\r\n\r\nMAI-Image-2.6\r\n"))
            #expect(body.contains("name=\"prompt\"\r\n\r\nЯблоко\r\nи груша\r\n"))
            #expect(body.contains("name=\"width\"\r\n\r\n1536\r\n"))
            #expect(body.contains("name=\"height\"\r\n\r\n1024\r\n"))
            #expect(body.contains("name=\"web_grounding\"\r\n\r\ntrue\r\n"))
            let png = try #require(body.range(of: "name=\"image\"; filename=\"image-1.png\"\r\nContent-Type: image/png\r\n\r\nPNG"))
            let jpeg = try #require(body.range(of: "name=\"image\"; filename=\"image-2.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nJPEG"))
            #expect(png.lowerBound < jpeg.lowerBound)
            #expect(!body.contains("name=\"mask\""))
            return maiResponse(request, body: #"{"usage":{"num_input_text_tokens":null,"num_input_image_tokens":7,"num_output_tokens":0},"data":[{"b64_json":"edited"}]}"#)
        }))
        let result = try await provider.image("MAI-Image-2.6").doGenerate(options: .init(
            prompt: "Яблоко\nи груша", n: 1, size: "1536x1024", aspectRatio: "9:16",
            files: [.file(mediaType: "IMAGE/PNG", data: .binary(Data("PNG".utf8)), providerOptions: nil),
                .file(mediaType: "image/jpeg", data: .base64("SlBFRw=="), providerOptions: nil)],
            mask: .url(url: "http://127.0.0.1/mask", providerOptions: nil),
            providerOptions: ["azure": ["webGrounding": true]]))
        #expect(result.images == .base64(["edited"]))
        #expect(result.usage == .init(inputTokens: 7, outputTokens: 0, totalTokens: 7))
        #expect(result.warnings == [
            .unsupported(feature: "mask", details: "MAI image edits do not support masks."),
            .unsupported(feature: "aspectRatio", details: "aspectRatio is ignored when size is set.")
        ])
    }

    @Test("Aspect ratios preserve the pixel budget and minimum side", arguments: [
        ("1:1", 1024, 1024), ("9:16", 768, 1360), ("4:3", 1168, 880), ("wide", nil, nil)
    ] as [(String, Int?, Int?)])
    func dimensions(_ ratio: String, _ width: Int?, _ height: Int?) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
            #expect(body["width"] == width.map { .number(Double($0)) })
            #expect(body["height"] == height.map { .number(Double($0)) })
            return maiResponse(request)
        }))
        let result = try await provider.image("MAI-Image-2.6").doGenerate(options: .init(n: 1, aspectRatio: ratio, files: []))
        #expect(result.images == .base64(["image"]))
        #expect(result.warnings == (width == nil ? [.unsupported(feature: "aspectRatio", details: "Invalid aspect ratio: \(ratio).")] : []))
    }

    @Test("Invalid options fail before reaching either API", arguments: [
        ["api": .string("speech")], ["api": .null], ["autoAspectRatio": .null], ["webGrounding": .number(1)]
    ] as [JSONObject])
    func optionValidation(_ fields: JSONObject) async throws {
        let provider = try createAzure(settings: .init(fetch: { _ in throw URLError(.cannotConnectToHost) }))
        let error = await #expect(throws: InvalidArgumentError.self) {
            try await provider.image("MAI-Image-2.6").doGenerate(options: .init(n: 1, providerOptions: ["azure": fields]))
        }
        #expect(error?.argument == "providerOptions")
    }

    @Test("Overflowing MAI usage is a typed response failure")
    func usageOverflow() async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: {
            maiResponse($0, body: #"{"usage":{"num_input_text_tokens":5000000000000000000,"num_output_tokens":5000000000000000000},"data":[{"b64_json":"image"}]}"#)
        }))
        _ = await #expect(throws: InvalidResponseDataError.self) {
            try await provider.image("MAI-Image-2.6").doGenerate(options: .init(n: 1))
        }
    }

    @Test("Cancelling MAI generation releases its active API request", arguments: [false, true])
    func cancellation(_ signal: Bool) async throws {
        let started = AsyncStream<Void>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        let aborted = MaiFlag()
        let timedOut = MaiFlag()
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { _ in
            started.continuation.yield(())
            do { try await Task.sleep(for: .seconds(30)) }
            catch { stopped.continuation.yield(()); throw error }
            throw URLError(.timedOut)
        }))
        let abortSignal: (@Sendable () -> Bool)?
        if signal { abortSignal = { aborted.value } } else { abortSignal = nil }
        let operation = Task {
            try await provider.image("MAI-Image-2.6").doGenerate(options: .init(n: 1, abortSignal: abortSignal))
        }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            timedOut.set()
            operation.cancel()
            started.continuation.finish()
            stopped.continuation.finish()
        }
        defer { watchdog.cancel(); operation.cancel() }
        var requests = started.stream.makeAsyncIterator()
        _ = try #require(await requests.next())
        if signal { aborted.set() } else { operation.cancel() }
        _ = await #expect(throws: CancellationError.self) { try await operation.value }
        var ended = stopped.stream.makeAsyncIterator()
        _ = try #require(await ended.next())
        #expect(!timedOut.value)
    }

    @Test("MAI errors and malformed responses retain HTTP diagnostics", arguments: [
        (400, #"{"error":{"code":42,"message":"width rejected"}}"#),
        (502, "<html>Bad Gateway</html>"),
        (200, #"{"data":[{"url":"https://example.com/image.png"}]}"#)
    ])
    func failures(_ status: Int, _ body: String) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key",
            fetch: { maiResponse($0, body: body, status: status) }))
        let error = await #expect(throws: APICallError.self) {
            try await provider.image("MAI-Image-2.6").doGenerate(options: .init(n: 1, size: "512x512"))
        }
        #expect(error?.statusCode == status)
        #expect(error?.responseBody == body)
        #expect(error?.responseHeaders?["x-request-id"] == "mai-request")
        if status == 400 { #expect(error?.message == "width rejected") }
    }
}
