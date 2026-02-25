import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ByteDanceProvider

@Suite("ByteDanceVideoModel")
struct ByteDanceVideoModelTests {
    private let prompt = "A futuristic city with flying cars"
    private let baseURL = "https://ark.ap-southeast.bytepluses.com/api/v3"

    private var createTasksURL: String {
        "\(baseURL)/contents/generations/tasks"
    }

    private func statusURL(taskId: String) -> String {
        "\(baseURL)/contents/generations/tasks/\(taskId)"
    }

    private static func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private static func httpResponse(url: URL, statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private actor HTTPStub {
        typealias Handler = @Sendable (URLRequest) async throws -> FetchResponse

        private var handlers: [String: Handler] = [:]
        private var calls: [URLRequest] = []

        func setJSON(
            method: String,
            url: String,
            statusCode: Int = 200,
            body: Any,
            headers: [String: String]? = nil
        ) async throws {
            let data = try ByteDanceVideoModelTests.jsonData(body)
            var headerFields: [String: String] = [
                "Content-Type": "application/json",
                "Content-Length": String(data.count),
            ]
            if let headers {
                for (key, value) in headers {
                    headerFields[key] = value
                }
            }

            let headerFieldsFinal = headerFields
            setHandler(method: method, url: url) { request in
                FetchResponse(
                    body: .data(data),
                    urlResponse: ByteDanceVideoModelTests.httpResponse(url: request.url!, statusCode: statusCode, headers: headerFieldsFinal)
                )
            }
        }

        func setRaw(
            method: String,
            url: String,
            statusCode: Int,
            body: Data,
            headers: [String: String]? = nil
        ) {
            var headerFields: [String: String] = [
                "Content-Type": "application/json",
                "Content-Length": String(body.count),
            ]
            if let headers {
                for (key, value) in headers {
                    headerFields[key] = value
                }
            }

            let headerFieldsFinal = headerFields
            setHandler(method: method, url: url) { request in
                FetchResponse(
                    body: .data(body),
                    urlResponse: ByteDanceVideoModelTests.httpResponse(url: request.url!, statusCode: statusCode, headers: headerFieldsFinal)
                )
            }
        }

        func setHandler(method: String, url: String, handler: @escaping Handler) {
            handlers["\(method.uppercased()) \(url)"] = handler
        }

        func handle(_ request: URLRequest) async throws -> FetchResponse {
            calls.append(request)
            let method = request.httpMethod ?? "GET"
            let url = request.url?.absoluteString ?? ""
            let key = "\(method.uppercased()) \(url)"
            guard let handler = handlers[key] else {
                throw ByteDanceProviderTestError(message: "Unexpected request: \(key)")
            }
            return try await handler(request)
        }

        func request(at index: Int) -> URLRequest? {
            guard index >= 0, index < calls.count else { return nil }
            return calls[index]
        }

        func count() -> Int {
            calls.count
        }
    }

    private struct ByteDanceProviderTestError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private final class AbortFlag: @unchecked Sendable {
        private var value = false
        private let lock = NSLock()

        func abort() {
            lock.lock()
            value = true
            lock.unlock()
        }

        @Sendable func signal() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private final class LockedCounter: @unchecked Sendable {
        private var valueStorage: Int = 0
        private let lock = NSLock()

        func increment() -> Int {
            lock.lock()
            valueStorage += 1
            let value = valueStorage
            lock.unlock()
            return value
        }

        func value() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return valueStorage
        }
    }

    private func decodeRequestBody(_ request: URLRequest) throws -> JSONValue {
        guard let body = request.httpBody else {
            return .null
        }
        return try JSONDecoder().decode(JSONValue.self, from: body)
    }

    private func makeModel(
        modelId: ByteDanceVideoModelId = .seedance10Pro250528,
        headers: (@Sendable () throws -> [String: String?])? = { ["Authorization": "Bearer test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> ByteDanceVideoModel {
        ByteDanceVideoModel(
            modelId: modelId,
            config: ByteDanceVideoModelConfig(
                provider: "bytedance.video",
                baseURL: baseURL,
                headers: headers ?? { [:] },
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private var defaultOptions: VideoModelV3CallOptions {
        VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        )
    }

    @Test("constructor exposes correct provider and model information")
    func constructorInfo() async throws {
        let model = makeModel()

        #expect(model.provider == "bytedance.video")
        #expect(model.modelId == "seedance-1-0-pro-250528")
        #expect(model.specificationVersion == "v3")

        switch model.maxVideosPerCall {
        case .value(let value):
            #expect(value == 1)
        case .default, .function:
            Issue.record("Expected fixed maxVideosPerCall == 1")
        }
    }

    @Test("constructor supports different model IDs")
    func constructorDifferentModelId() async throws {
        let model = makeModel(modelId: .seedance15Pro251215)
        #expect(model.modelId == "seedance-1-5-pro-251215")
    }

    @Test("constructor supports custom model IDs")
    func constructorCustomModelId() async throws {
        let model = makeModel(modelId: "custom-model-id")
        #expect(model.modelId == "custom-model-id")
    }

    @Test("doGenerate passes the correct parameters including prompt")
    func passesPrompt() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(
            method: "POST",
            url: createTasksURL,
            body: ["id": "test-task-id-123"]
        )
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "model": "seedance-1-0-pro-250528",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
                "usage": ["completion_tokens": 100],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: defaultOptions)

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
        ]))
    }

    @Test("doGenerate passes seed when provided")
    func passesSeed() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, seed: 42, providerOptions: [:]))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "seed": .number(42),
        ]))
    }

    @Test("doGenerate passes aspect ratio when provided")
    func passesAspectRatio() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, aspectRatio: "16:9", providerOptions: [:]))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "ratio": .string("16:9"),
        ]))
    }

    @Test("doGenerate passes duration when provided")
    func passesDuration() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, duration: 5, providerOptions: [:]))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "duration": .number(5),
        ]))
    }

    @Test("doGenerate maps WxH resolution to API format")
    func mapsResolution1080p() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, resolution: "1920x1080", providerOptions: [:]))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "resolution": .string("1080p"),
        ]))
    }

    @Test("doGenerate maps 720p resolution correctly")
    func mapsResolution720p() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, resolution: "1280x720", providerOptions: [:]))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "resolution": .string("720p"),
        ]))
    }

    @Test("doGenerate maps 480p resolution correctly")
    func mapsResolution480p() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, resolution: "864x480", providerOptions: [:]))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "resolution": .string("480p"),
        ]))
    }

    @Test("doGenerate passes through unmapped resolution values")
    func passesThroughResolution() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, resolution: "640x480", providerOptions: [:]))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "resolution": .string("640x480"),
        ]))
    }

    @Test("doGenerate merges headers")
    func mergesHeaders() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(headers: { ["Custom-Provider-Header": "provider-header-value"] }, fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [:],
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
    }

    @Test("doGenerate returns video with correct data")
    func returnsVideoData() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.videos.count == 1)
        #expect(result.videos[0] == .url(url: "https://bytedance.cdn/files/video-output.mp4", mediaType: "video/mp4"))
    }

    @Test("doGenerate returns warnings array")
    func returnsWarningsArray() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: defaultOptions)
        #expect(result.warnings == [])
    }

    @Test("warnings: fps is unsupported")
    func warnsOnFPS() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, fps: 30, providerOptions: [:]))

        #expect(result.warnings.contains(.unsupported(
            feature: "fps",
            details: "ByteDance video models do not support custom FPS. Frame rate is fixed at 24 fps."
        )))
    }

    @Test("warnings: n > 1 is unsupported")
    func warnsOnN() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 3, providerOptions: [:]))

        #expect(result.warnings.contains(.unsupported(
            feature: "n",
            details: "ByteDance video models do not support generating multiple videos per call. Only 1 video will be generated."
        )))
    }

    @Test("response metadata includes timestamp, headers and modelId")
    func responseMetadata() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ],
            headers: [
                "X-Test": "1"
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let testDate = Date(timeIntervalSince1970: 1_704_067_200)
        let model = makeModel(fetch: fetch, currentDate: { testDate })
        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "seedance-1-0-pro-250528")
        #expect(result.response.headers?["x-test"] == "1")
    }

    @Test("providerMetadata includes task ID and usage")
    func providerMetadata() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "model": "seedance-1-0-pro-250528",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
                "usage": ["completion_tokens": 100],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.providerMetadata == [
            "bytedance": [
                "taskId": .string("test-task-id-123"),
                "usage": .object([
                    "completion_tokens": .number(100)
                ])
            ]
        ])
    }

    @Test("Image-to-Video sends image_url with file data")
    func imageToVideoFile() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
            providerOptions: [:]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("data:image/png;base64,iVBORw==")
                    ])
                ])
            ]),
        ]))
    }

    @Test("Image-to-Video sends image_url with URL-based image")
    func imageToVideoURL() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/input-image.png", providerOptions: nil),
            providerOptions: [:]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("https://example.com/input-image.png")
                    ])
                ])
            ]),
        ]))
    }

    @Test("Provider options: watermark is passed through")
    func providerOptionsWatermark() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "watermark": true
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "watermark": .bool(true),
        ]))
    }

    @Test("Provider options: generateAudio maps to generate_audio")
    func providerOptionsGenerateAudio() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "generateAudio": true
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "generate_audio": .bool(true),
        ]))
    }

    @Test("Provider options: cameraFixed maps to camera_fixed")
    func providerOptionsCameraFixed() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "cameraFixed": true
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "camera_fixed": .bool(true),
        ]))
    }

    @Test("Provider options: returnLastFrame maps to return_last_frame")
    func providerOptionsReturnLastFrame() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "returnLastFrame": true
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "return_last_frame": .bool(true),
        ]))
    }

    @Test("Provider options: serviceTier maps to service_tier")
    func providerOptionsServiceTier() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "serviceTier": "flex"
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "service_tier": .string("flex"),
        ]))
    }

    @Test("Provider options: draft is passed through")
    func providerOptionsDraft() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(modelId: .seedance15Pro251215, fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "draft": true
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-5-pro-251215"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "draft": .bool(true),
        ]))
    }

    @Test("Provider options: adds last frame image with role")
    func providerOptionsLastFrameImage() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(modelId: .seedance15Pro251215, fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/first-frame.png", providerOptions: nil),
            providerOptions: [
                "bytedance": [
                    "lastFrameImage": "https://example.com/last-frame.png"
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-5-pro-251215"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("https://example.com/first-frame.png")
                    ]),
                ]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("https://example.com/last-frame.png")
                    ]),
                    "role": .string("last_frame"),
                ]),
            ])
        ]))
    }

    @Test("Provider options: adds reference images with role")
    func providerOptionsReferenceImages() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(modelId: .seedance10LiteI2v250428, fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "referenceImages": [
                        "https://example.com/ref1.png",
                        "https://example.com/ref2.png",
                        "https://example.com/ref3.png",
                    ]
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-lite-i2v-250428"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("https://example.com/ref1.png")
                    ]),
                    "role": .string("reference_image"),
                ]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("https://example.com/ref2.png")
                    ]),
                    "role": .string("reference_image"),
                ]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("https://example.com/ref3.png")
                    ]),
                    "role": .string("reference_image"),
                ]),
            ])
        ]))
    }

    @Test("Provider options: passes through additional options")
    func providerOptionsPassthrough() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "test-task-id-123"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "test-task-id-123"),
            body: [
                "id": "test-task-id-123",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/video-output.mp4"],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "custom_param": "custom_value",
                    "another_param": 123,
                ]
            ]
        ))

        guard let request = await stub.request(at: 0) else {
            Issue.record("Missing request capture")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json == .object([
            "model": .string("seedance-1-0-pro-250528"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ])
            ]),
            "custom_param": .string("custom_value"),
            "another_param": .number(123),
        ]))
    }

    @Test("Error handling: throws when no task ID is returned")
    func errorNoTaskId() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createTasksURL, body: [:])

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message == "No task ID returned from API")
        }
    }

    @Test("Error handling: throws when task fails")
    func errorTaskFailed() async throws {
        let stub = HTTPStub()

        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "failed-task-id"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "failed-task-id"),
            body: [
                "id": "failed-task-id",
                "status": "failed",
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [
                    "bytedance": [
                        "pollIntervalMs": 10
                    ]
                ]
            ))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message.contains("Video generation failed"))
        }
    }

    @Test("Error handling: throws when no video URL in response")
    func errorNoVideoURL() async throws {
        let stub = HTTPStub()

        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "no-video-task-id"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "no-video-task-id"),
            body: [
                "id": "no-video-task-id",
                "status": "succeeded",
                "content": [:],
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [
                    "bytedance": [
                        "pollIntervalMs": 10
                    ]
                ]
            ))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message == "No video URL in response")
        }
    }

    @Test("Error handling: handles API errors from task creation")
    func errorTaskCreationAPIError() async throws {
        let stub = HTTPStub()

        let errorData = try Self.jsonData([
            "error": ["message": "Invalid prompt"]
        ])
        await stub.setRaw(method: "POST", url: createTasksURL, statusCode: 400, body: errorData)

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
        }
    }

    @Test("Polling: polls until video is ready")
    func pollingUntilReady() async throws {
        let stub = HTTPStub()

        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "poll-test-id"])

        let pollCount = LockedCounter()
        await stub.setHandler(method: "GET", url: statusURL(taskId: "poll-test-id")) { request in
            let currentCount = pollCount.increment()

            if currentCount < 3 {
                let data = try JSONSerialization.data(withJSONObject: [
                    "id": "poll-test-id",
                    "status": "processing",
                ], options: [.sortedKeys])

                return FetchResponse(
                    body: .data(data),
                    urlResponse: Self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }

            let data = try JSONSerialization.data(withJSONObject: [
                "id": "poll-test-id",
                "status": "succeeded",
                "content": ["video_url": "https://bytedance.cdn/files/final-video.mp4"],
                "usage": ["completion_tokens": 100],
            ], options: [.sortedKeys])

            return FetchResponse(
                body: .data(data),
                urlResponse: Self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
            )
        }

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "bytedance": [
                    "pollIntervalMs": 10
                ]
            ]
        ))

        #expect(pollCount.value() == 3)
        #expect(result.videos.first == .url(url: "https://bytedance.cdn/files/final-video.mp4", mediaType: "video/mp4"))
    }

    @Test("Polling: times out after pollTimeoutMs")
    func pollingTimeout() async throws {
        let stub = HTTPStub()

        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "timeout-test-id"])
        try await stub.setJSON(
            method: "GET",
            url: statusURL(taskId: "timeout-test-id"),
            body: [
                "id": "timeout-test-id",
                "status": "processing",
            ]
        )

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [
                    "bytedance": [
                        "pollIntervalMs": 10,
                        "pollTimeoutMs": 50,
                    ]
                ]
            ))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message.contains("timed out"))
        }
    }

    @Test("Polling: respects abort signal")
    func pollingAbort() async throws {
        let stub = HTTPStub()
        let abortFlag = AbortFlag()

        try await stub.setJSON(method: "POST", url: createTasksURL, body: ["id": "abort-test-id"])

        await stub.setHandler(method: "GET", url: statusURL(taskId: "abort-test-id")) { request in
            abortFlag.abort()
            let data = try JSONSerialization.data(withJSONObject: [
                "id": "abort-test-id",
                "status": "processing",
            ], options: [.sortedKeys])

            return FetchResponse(
                body: .data(data),
                urlResponse: Self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
            )
        }

        let fetch: FetchFunction = { request in
            try await stub.handle(request)
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [
                    "bytedance": [
                        "pollIntervalMs": 10
                    ]
                ],
                abortSignal: abortFlag.signal
            ))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message.contains("aborted"))
        }
    }
}
