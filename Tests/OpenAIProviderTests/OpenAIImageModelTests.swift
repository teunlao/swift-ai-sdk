import Foundation
import ObjectiveC
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

private actor ImageRequests {
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
    func first() -> URLRequest? { requests.first }
}

private func imageResponse(_ request: URLRequest, body: String = #"{"data":[{"b64_json":"image"}]}"#, status: Int = 200) -> FetchResponse {
    FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json", "X-Request-Id": "image-request"]
    )!)
}

private final class ImageFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private final class ImageDownload: @unchecked Sendable {
    let started = AsyncStream<URLRequest>.makeStream()
    let stopped = AsyncStream<Void>.makeStream()
    let hangs: Bool
    init(hangs: Bool = false) { self.hangs = hangs }
}

private final class ImageURLProtocol: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var download: ImageDownload?
    }
    private static let state = State()
    private let requestState = State()
    static func use(_ download: ImageDownload?) { state.lock.withLock { state.download = download } }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "93.184.216.34" && request.url?.path.hasPrefix("/swift-ai-sdk-image/") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let download = Self.state.lock.withLock({ Self.state.download }) else { return }
        requestState.lock.withLock { requestState.download = download }
        let probe = request.url?.path.hasSuffix("/probe") == true
        if !probe { download.started.continuation.yield(request) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0x89, 0x50, 0x4E, 0x47]))
        if probe || !download.hangs { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {
        let download = requestState.lock.withLock {
            let download = requestState.download
            requestState.download = nil
            return download
        }
        if request.url?.path.hasSuffix("/probe") != true { download?.stopped.continuation.yield(()) }
    }
}

private final class ImageTransport {
    private typealias TaskFactory = @convention(c) (AnyObject, Selector, NSURLRequest) -> URLSessionDataTask
    private final class Routing: @unchecked Sendable {
        let lock = NSLock()
        var session: URLSession?
        init(_ session: URLSession) { self.session = session }
    }
    private let method: Method
    private let original: IMP
    private let routing: Routing
    private let session: URLSession
    private var active = true
    private static let marker = "swift-ai-sdk.image-fixture"
    private static let probe = URL(string: "https://93.184.216.34/swift-ai-sdk-image/probe")!

    init(_ download: ImageDownload) throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        self.session = session
        let routing = Routing(session)
        self.routing = routing
        let selector = NSSelectorFromString("dataTaskWithRequest:")
        guard let method = class_getInstanceMethod(object_getClass(URLSession.shared), selector) else {
            session.invalidateAndCancel()
            throw URLError(.unsupportedURL)
        }
        self.method = method
        let original = method_getImplementation(method)
        self.original = original
        let createTask = unsafeBitCast(original, to: TaskFactory.self)
        let intercept: @convention(block) (URLSession, NSURLRequest) -> URLSessionDataTask = { receiver, request in
            guard ImageURLProtocol.canInit(with: request as URLRequest),
                  let fixture = routing.lock.withLock({ routing.session }) else {
                return createTask(receiver, selector, request)
            }
            let marked = request.mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(true, forKey: ImageTransport.marker, in: marked)
            return createTask(fixture, selector, marked)
        }
        ImageURLProtocol.use(download)
        method_setImplementation(method, imp_implementationWithBlock(intercept))
    }

    func verify() async throws {
        let ordinary = URLSession(configuration: .default)
        defer { ordinary.invalidateAndCancel() }
        let request = URLRequest(url: Self.probe)
        for receiver in [URLSession.shared, ordinary] {
            let task = receiver.dataTask(with: request)
            defer { task.cancel() }
            guard let original = task.originalRequest,
                  URLProtocol.property(forKey: Self.marker, in: original) as? Bool == true else {
                throw URLError(.unsupportedURL)
            }
        }
        let response = try await defaultFetchFunction()(request)
        guard try await response.body.collectData() == Data([0x89, 0x50, 0x4E, 0x47]) else {
            throw URLError(.badServerResponse)
        }
    }

    func close() {
        guard active else { return }
        active = false
        method_setImplementation(method, original)
        // Keep block IMPs alive for calls resolved before restoration.
        routing.lock.withLock { routing.session = nil }
        session.invalidateAndCancel()
        ImageURLProtocol.use(nil)
    }

    deinit { close() }
}

@Suite("OpenAIImageModel", .serialized)
struct OpenAIImageModelTests {
    @Test("generation maps options, headers, usage, warnings and image metadata")
    func generation() async throws {
        let requests = ImageRequests()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "image-key", organization: "image-org", project: "image-project",
            headers: ["X-Image-Header": "configured"], fetch: { request in
                await requests.append(request)
                return imageResponse(request, body: #"{"created":1234.5,"data":[{"b64_json":"first","revised_prompt":"revised"},{"b64_json":"second","revised_prompt":""}],"size":"1024x1024","quality":"high","background":"opaque","output_format":"png","usage":{"input_tokens":12,"output_tokens":0,"total_tokens":12,"input_tokens_details":{"image_tokens":-5,"text_tokens":3}}}"#)
            }
        ))
        let before = Date()
        let result = try await provider.image("dall-e-3").doGenerate(options: .init(
            prompt: "otter", n: 2, size: "1024x1024", aspectRatio: "1:1", seed: 42,
            providerOptions: ["openai": ["quality": "high", "style": "vivid", "background": "opaque",
                "moderation": "low", "outputFormat": "png", "outputCompression": 80, "user": "user"]],
            headers: ["X-Image-Header": "caller"]
        ))
        let request = try #require(await requests.first())
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body == .object(["model": "dall-e-3", "prompt": "otter", "n": 2, "size": "1024x1024",
            "quality": "high", "style": "vivid", "background": "opaque", "moderation": "low",
            "output_format": "png", "output_compression": 80, "user": "user", "response_format": "b64_json"]))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/generations")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer image-key")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == "image-org")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == "image-project")
        #expect(request.value(forHTTPHeaderField: "X-Image-Header") == "caller")
        #expect(result.images == .base64(["first", "second"]))
        #expect(result.usage == .init(inputTokens: 12, outputTokens: 0, totalTokens: 12))
        #expect(result.warnings == [.unsupported(feature: "aspectRatio", details: "This model does not support aspect ratio. Use `size` instead."), .unsupported(feature: "seed", details: nil)])
        #expect(result.response.timestamp >= before && result.response.timestamp <= Date())
        #expect(result.response.modelId == "dall-e-3")
        #expect(result.response.headers?["x-request-id"] == "image-request")
        #expect(result.providerMetadata?["openai"]?.images == [
            .object(["revisedPrompt": "revised", "created": 1234.5, "size": "1024x1024", "quality": "high",
                "background": "opaque", "outputFormat": "png", "imageTokens": -3, "textTokens": 1]),
            .object(["created": 1234.5, "size": "1024x1024", "quality": "high",
                "background": "opaque", "outputFormat": "png", "imageTokens": -2, "textTokens": 2])
        ])
    }

    @Test("model defaults select request format, capacity and editing capabilities", arguments: [
        ("dall-e-3", 1, false, false), ("dall-e-2", 10, true, false),
        ("gpt-image-2.5-flare", 10, true, true), ("gpt-image-2.5-sunburst-2026-09-08", 10, true, true),
        ("gpt-image-future", 10, nil, true), ("chatgpt-image-custom", 1, nil, true), ("custom", 1, nil, false)
    ] as [(String, Int, Bool?, Bool)])
    func defaults(_ id: String, _ count: Int, _ supports: Bool?, _ defaultFormat: Bool) async throws {
        let requests = ImageRequests()
        let model: any ImageModelV4 = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            await requests.append(request)
            return imageResponse(request)
        })).image(id)
        #expect(try await model.supportsFileInputs == supports)
        #expect(try await model.supportsMaskInputs == supports)
        guard case .value(let capacity) = model.maxImagesPerCall else { Issue.record("Missing capacity"); return }
        #expect(capacity == count)
        _ = try await model.doGenerate(options: .init(n: 1))
        let body = try JSONDecoder().decode([String: JSONValue].self, from: #require(await requests.first()?.httpBody))
        #expect(body == ["model": .string(id), "n": 1].merging(defaultFormat ? [:] : ["response_format": "b64_json"]) { _, rhs in rhs })
    }

    @Test("capability overrides preserve unknown fields and custom timestamps", arguments: [
        (nil, false), (true, nil)
    ] as [(Bool?, Bool?)])
    func overrides(_ files: Bool?, _ masks: Bool?) async throws {
        let model: any ImageModelV4 = OpenAIImageModel(modelId: "dall-e-2", config: .init(
            provider: "custom.image", imageInputCapabilities: .init(supportsFileInputs: files, supportsMaskInputs: masks),
            url: { "https://example.com\($0.path)" }, fetch: { imageResponse($0) },
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 42) })
        ))
        #expect(try await model.supportsFileInputs == files)
        #expect(try await model.supportsMaskInputs == masks)
        let result = try await model.doGenerate(options: .init(n: 1))
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 42))
        #expect(result.usage == nil)
    }

    @Test("edits preserve binary/base64 files and mask with native FormData fields")
    func edits() async throws {
        let requests = ImageRequests()
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            await requests.append(request)
            return imageResponse(request)
        })).image("gpt-image-1")
        let result = try await model.doGenerate(options: .init(
            prompt: "edit\nimage", n: 1, size: "1024x1024", files: [
                .file(mediaType: "IMAGE/PNG", data: .binary(Data("PNG".utf8)), providerOptions: nil),
                .file(mediaType: "image/jpeg", data: .base64("SlBFRw=="), providerOptions: nil)
            ], mask: .file(mediaType: "image/png", data: .binary(Data("MASK".utf8)), providerOptions: nil),
            providerOptions: ["openai": ["quality": "high", "background": "transparent", "outputFormat": "webp",
                "outputCompression": 80, "inputFidelity": "high", "user": "user"]]
        ))
        let request = try #require(await requests.first())
        #expect(request.url?.path == "/v1/images/edits")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("name=\"image[]\"; filename=\"blob\"\r\nContent-Type: image/png\r\n\r\nPNG"))
        #expect(body.contains("name=\"image[]\"; filename=\"blob\"\r\nContent-Type: image/jpeg\r\n\r\nJPEG"))
        #expect(body.contains("name=\"mask\"; filename=\"blob\"\r\nContent-Type: image/png\r\n\r\nMASK"))
        for (field, value) in ["model": "gpt-image-1", "prompt": "edit\r\nimage", "n": "1", "size": "1024x1024",
            "quality": "high", "background": "transparent", "output_format": "webp", "output_compression": "80",
            "input_fidelity": "high", "user": "user"] {
            #expect(body.contains("name=\"\(field)\"\r\n\r\n\(value)\r\n"))
        }
        let image = try #require(body.range(of: "name=\"image[]\""))
        let mask = try #require(body.range(of: "name=\"mask\""))
        let count = try #require(body.range(of: "name=\"n\""))
        #expect(image.lowerBound < mask.lowerBound && mask.lowerBound < count.lowerBound)
        #expect(result.images == .base64(["image"]))
    }

    @Test("an empty files array selects edits and omits the image part")
    func emptyEdits() async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/v1/images/edits")
            let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
            #expect(body.contains("name=\"model\"\r\n\r\ngpt-image-1\r\n"))
            #expect(!body.contains("name=\"image\""))
            return imageResponse(request, body: #"{"data":[]}"#)
        })).image("gpt-image-1")
        let result = try await model.doGenerate(options: .init(n: 1, files: []))
        #expect(result.images == .base64([]))
        #expect(result.providerMetadata?["openai"]?.images == [])
    }

    @Test("invalid API responses retain diagnostics rather than inventing URL output", arguments: [
        #"{"data":[{"url":"https://example.com/image.png"}]}"#,
        #"{"data":[{"b64_json":17}]}"#
    ])
    func responseValidation(_ body: String) async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { imageResponse($0, body: body) })).image("gpt-image-1")
        let error = await #expect(throws: APICallError.self) { try await model.doGenerate(options: .init(n: 1)) }
        #expect(error?.statusCode == 200)
        #expect(error?.responseBody == body)
    }

    @Test("API errors preserve the provider message and multipart request values")
    func apiError() async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: {
            imageResponse($0, body: #"{"error":{"message":"image denied","type":"invalid_request_error"}}"#, status: 403)
        })).image("dall-e-3")
        let error = await #expect(throws: APICallError.self) {
            try await model.doGenerate(options: .init(prompt: "edit\nimage", n: 1,
                files: [.file(mediaType: "IMAGE/PNG", data: .binary(Data([0xFF])), providerOptions: nil)]))
        }
        #expect(error?.statusCode == 403)
        #expect(error?.message == "image denied")
        #expect(error?.requestBodyValues as? [String: FormDataValue] == [
            "model": .string("dall-e-3"), "prompt": .string("edit\nimage"), "n": .string("1"),
            "image": .data(Data([0xFF]), contentType: "image/png")
        ])
    }

    @Test("URL image and mask use the default download transport with isolated headers")
    func downloads() async throws {
        let download = ImageDownload()
        let transport = try ImageTransport(download)
        defer { transport.close() }
        try await transport.verify()
        let model = try createOpenAIProvider(settings: .init(
            baseURL: "https://93.184.216.34/v1", apiKey: "secret-key", headers: ["X-Image-Secret": "secret-header"],
            fetch: { request in
                #expect(request.url?.path == "/v1/images/edits")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
                #expect(request.value(forHTTPHeaderField: "X-Image-Secret") == "secret-header")
                #expect(request.value(forHTTPHeaderField: "X-Image-Caller") == "caller-header")
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(body.contains("name=\"image\"; filename=\"blob\"\r\nContent-Type: image/png"))
                #expect(body.contains("name=\"mask\"; filename=\"blob\"\r\nContent-Type: image/png"))
                return imageResponse(request)
            }
        )).image("gpt-image-1")
        let operation = Task {
            try await model.doGenerate(options: .init(n: 1,
                files: [.url(url: "https://93.184.216.34/swift-ai-sdk-image/image", providerOptions: nil)],
                mask: .url(url: "https://93.184.216.34/swift-ai-sdk-image/mask", providerOptions: nil),
                headers: ["X-Image-Caller": "caller-header"]
            ))
        }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            operation.cancel()
            download.started.continuation.finish()
        }
        defer { watchdog.cancel(); operation.cancel() }
        _ = try await operation.value
        var requests = download.started.stream.makeAsyncIterator()
        for _ in 0..<2 {
            let request = try #require(await requests.next())
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Image-Secret") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Image-Caller") == nil)
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.isEmpty == false)
        }
    }

    @Test("aborting a URL image or mask releases the active download", arguments: [false, true])
    func abortDownload(_ mask: Bool) async throws {
        let download = ImageDownload(hangs: true)
        let transport = try ImageTransport(download)
        defer { transport.close() }
        try await transport.verify()
        let aborted = ImageFlag()
        let timedOut = ImageFlag()
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { _ in
            Issue.record("An aborted download must not reach the API")
            throw CancellationError()
        })).image("gpt-image-1")
        let url = ImageModelV4File.url(url: "https://93.184.216.34/swift-ai-sdk-image/hanging", providerOptions: nil)
        let operation = Task {
            try await model.doGenerate(options: .init(n: 1,
                files: mask ? [] : [url], mask: mask ? url : nil, abortSignal: { aborted.value }))
        }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            timedOut.set()
            operation.cancel()
            download.started.continuation.finish()
            download.stopped.continuation.finish()
        }
        defer { watchdog.cancel(); operation.cancel() }
        var started = download.started.stream.makeAsyncIterator()
        _ = try #require(await started.next())
        aborted.set()
        _ = await #expect(throws: DownloadError.self) { try await operation.value }
        #expect(!timedOut.value)
        var stopped = download.stopped.stream.makeAsyncIterator()
        _ = try #require(await stopped.next())
    }
}
