import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import KlingAIProvider

@Suite("KlingAIVideoModel")
struct KlingAIVideoModelTests {
    private let prompt = "A character performs a graceful dance"
    private let testBaseURL = "https://api-singapore.klingai.com"

    private var motionControlCreateURL: String { "\(testBaseURL)/v1/videos/motion-control" }
    private var motionControlStatusURL: String { "\(testBaseURL)/v1/videos/motion-control/task-abc-123" }
    private var t2vCreateURL: String { "\(testBaseURL)/v1/videos/text2video" }
    private var t2vStatusURL: String { "\(testBaseURL)/v1/videos/text2video/task-abc-123" }
    private var i2vCreateURL: String { "\(testBaseURL)/v1/videos/image2video" }
    private var i2vStatusURL: String { "\(testBaseURL)/v1/videos/image2video/task-abc-123" }

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
            body: JSONValue,
            headers: [String: String]? = nil
        ) async throws {
            let data = try JSONEncoder().encode(body)
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
                    urlResponse: KlingAIVideoModelTests.httpResponse(url: request.url!, statusCode: statusCode, headers: headerFieldsFinal)
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
                struct UnexpectedRequest: Error, CustomStringConvertible {
                    let description: String
                }
                throw UnexpectedRequest(description: "Unexpected request: \(key)")
            }
            return try await handler(request)
        }

        func request(at index: Int) -> URLRequest? {
            guard index >= 0, index < calls.count else { return nil }
            return calls[index]
        }
    }

    private let createTaskResponse: JSONValue = .object([
        "code": .number(0),
        "message": .string("success"),
        "request_id": .string("req-001"),
        "data": .object([
            "task_id": .string("task-abc-123"),
            "task_status": .string("submitted"),
            "task_info": .object(["external_task_id": .null]),
            "created_at": .number(1_722_769_557_708),
            "updated_at": .number(1_722_769_557_708),
        ])
    ])

    private let successfulTaskResponse: JSONValue = .object([
        "code": .number(0),
        "message": .string("success"),
        "request_id": .string("req-002"),
        "data": .object([
            "task_id": .string("task-abc-123"),
            "task_status": .string("succeed"),
            "task_status_msg": .string(""),
            "task_info": .object(["external_task_id": .null]),
            "watermark_info": .object(["enabled": .bool(false)]),
            "final_unit_deduction": .string("1"),
            "created_at": .number(1_722_769_557_708),
            "updated_at": .number(1_722_769_560_000),
            "task_result": .object([
                "videos": .array([
                    .object([
                        "id": .string("video-001"),
                        "url": .string("https://p1.a.kwimgs.com/output/video-001.mp4"),
                        "watermark_url": .string("https://p1.a.kwimgs.com/output/video-001-watermark.mp4"),
                        "duration": .string("5.0"),
                    ])
                ])
            ]),
        ])
    ])

    private var motionControlProviderOptions: SharedV3ProviderOptions {
        [
            "klingai": [
                "videoUrl": .string("https://example.com/reference-motion.mp4"),
                "characterOrientation": .string("image"),
                "mode": .string("std"),
                "pollIntervalMs": .number(10),
                "pollTimeoutMs": .number(5000),
            ]
        ]
    }

    private var t2vProviderOptions: SharedV3ProviderOptions {
        [
            "klingai": [
                "mode": .string("std"),
                "pollIntervalMs": .number(10),
                "pollTimeoutMs": .number(5000),
            ]
        ]
    }

    private var i2vProviderOptions: SharedV3ProviderOptions {
        [
            "klingai": [
                "mode": .string("std"),
                "pollIntervalMs": .number(10),
                "pollTimeoutMs": .number(5000),
            ]
        ]
    }

    private func makeModel(
        modelId: KlingAIVideoModelId = .klingV26MotionControl,
        headers: (@Sendable () async throws -> [String: String?])? = { ["Authorization": "Bearer test-jwt-token"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> KlingAIVideoModel {
        KlingAIVideoModel(
            modelId: modelId,
            config: KlingAIVideoModelConfig(
                provider: "klingai.video",
                baseURL: testBaseURL,
                headers: headers ?? { [:] },
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private func configureDefaultSuccessResponses(_ stub: HTTPStub) async throws {
        try await stub.setJSON(method: "POST", url: motionControlCreateURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: motionControlStatusURL, body: successfulTaskResponse)
        try await stub.setJSON(method: "POST", url: t2vCreateURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: t2vStatusURL, body: successfulTaskResponse)
        try await stub.setJSON(method: "POST", url: i2vCreateURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: i2vStatusURL, body: successfulTaskResponse)
    }

    private func decodeRequestBody(_ request: URLRequest) throws -> JSONValue {
        guard let body = request.httpBody else { return .null }
        return try JSONDecoder().decode(JSONValue.self, from: body)
    }

    private func headersLowercased(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    private func objectContains(_ json: JSONValue, _ expected: [String: JSONValue]) -> Bool {
        guard case .object(let dict) = json else { return false }
        for (key, value) in expected {
            guard dict[key] == value else { return false }
        }
        return true
    }

    private func hasUnsupportedWarning(_ warnings: [SharedV3Warning], feature: String) -> Bool {
        warnings.contains {
            switch $0 {
            case .unsupported(let f, _):
                return f == feature
            default:
                return false
            }
        }
    }

    private func setKlingAIOption(
        _ options: inout SharedV3ProviderOptions,
        key: String,
        value: JSONValue
    ) {
        var dict = options["klingai"] ?? [:]
        dict[key] = value
        options["klingai"] = dict
    }

    private func configureFetch(stub: HTTPStub) -> FetchFunction {
        { request in
            try await stub.handle(request)
        }
    }

    @Test("constructor should expose correct provider and model information")
    func constructorInfo() async throws {
        let model = makeModel()

        #expect(model.provider == "klingai.video")
        #expect(model.modelId == "kling-v2.6-motion-control")
        #expect(model.specificationVersion == "v3")

        switch model.maxVideosPerCall {
        case .value(let value):
            #expect(value == 1)
        case .default, .function:
            Issue.record("Expected fixed maxVideosPerCall == 1")
        }
    }

    @Test("constructor should accept custom model IDs in constructor")
    func constructorCustomModelId() async throws {
        let model = makeModel(modelId: "kling-v2.6-t2v")
        #expect(model.modelId == "kling-v2.6-t2v")
    }

    @Test("constructor should throw NoSuchModelError for unknown model IDs on generate")
    func unknownModelIdThrows() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "unknown-model", fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: motionControlProviderOptions
            ))
            Issue.record("Expected error")
        } catch let error as NoSuchModelError {
            #expect(error.message.contains("No such videoModel: unknown-model"))
        }
    }

    // MARK: - Motion Control

    @Test("motion control: should send correct request body with required fields")
    func motionControlRequiredBody() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: motionControlProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)

        #expect(body == .object([
            "prompt": .string(prompt),
            "video_url": .string("https://example.com/reference-motion.mp4"),
            "character_orientation": .string("image"),
            "mode": .string("std"),
        ]))
    }

    @Test("motion control: should send prompt when provided")
    func motionControlPrompt() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: "Dance gracefully",
            n: 1,
            providerOptions: motionControlProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["prompt": .string("Dance gracefully")]))
    }

    @Test("motion control: should send image_url from URL-based image")
    func motionControlImageURL() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/reference-image.png", providerOptions: nil),
            providerOptions: motionControlProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["image_url": .string("https://example.com/reference-image.png")]))
    }

    @Test("motion control: should send image_url as base64 from file data")
    func motionControlImageFile() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
            providerOptions: motionControlProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["image_url": .string("iVBORw==")]))
    }

    @Test("motion control: should send keep_original_sound when provided")
    func motionControlKeepOriginalSound() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = motionControlProviderOptions
        setKlingAIOption(&options, key: "keepOriginalSound", value: .string("no"))

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["keep_original_sound": .string("no")]))
    }

    @Test("motion control: should send watermark_info when watermarkEnabled is set")
    func motionControlWatermarkInfo() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = motionControlProviderOptions
        setKlingAIOption(&options, key: "watermarkEnabled", value: .bool(true))

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["watermark_info": .object(["enabled": .bool(true)])]))
    }

    @Test("motion control: should pass headers to requests")
    func motionControlHeaders() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(
            headers: { ["Authorization": "Bearer custom-token", "X-Custom": "value"] },
            fetch: fetch
        )

        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: motionControlProviderOptions,
            headers: ["X-Request-Header": "request-value"]
        ))

        let request = try #require(await stub.request(at: 0))
        let headers = headersLowercased(request)
        #expect(headers["authorization"] == "Bearer custom-token")
        #expect(headers["x-custom"] == "value")
        #expect(headers["x-request-header"] == "request-value")
    }

    @Test("motion control: should return video with correct URL and media type")
    func motionControlReturnVideo() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: motionControlProviderOptions
        ))

        #expect(result.videos.count == 1)
        #expect(result.videos[0] == .url(url: "https://p1.a.kwimgs.com/output/video-001.mp4", mediaType: "video/mp4"))
    }

    @Test("motion control: should return empty warnings for supported features")
    func motionControlEmptyWarnings() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: motionControlProviderOptions
        ))

        #expect(result.warnings == [])
    }

    @Test("motion control: should warn about unsupported standard options")
    func motionControlUnsupportedWarnings() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 3,
            aspectRatio: "16:9",
            resolution: "1920x1080",
            duration: 10,
            fps: 30,
            seed: 42,
            providerOptions: motionControlProviderOptions
        ))

        #expect(hasUnsupportedWarning(result.warnings, feature: "aspectRatio"))
        #expect(hasUnsupportedWarning(result.warnings, feature: "resolution"))
        #expect(hasUnsupportedWarning(result.warnings, feature: "seed"))
        #expect(hasUnsupportedWarning(result.warnings, feature: "fps"))
        #expect(hasUnsupportedWarning(result.warnings, feature: "duration"))
        #expect(hasUnsupportedWarning(result.warnings, feature: "n"))
    }

    @Test("motion control: should not warn when n is 1")
    func motionControlDoesNotWarnOnNEqualsOne() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: motionControlProviderOptions
        ))

        #expect(!hasUnsupportedWarning(result.warnings, feature: "n"))
    }

    @Test("motion control: should send mode=pro when specified")
    func motionControlModePro() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let providerOptions: SharedV3ProviderOptions = [
            "klingai": [
                "videoUrl": .string("https://example.com/motion.mp4"),
                "characterOrientation": .string("video"),
                "mode": .string("pro"),
                "pollIntervalMs": .number(10),
            ]
        ]

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: providerOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, [
            "character_orientation": .string("video"),
            "mode": .string("pro"),
        ]))
    }

    // MARK: - Text-to-Video

    @Test("text-to-video: should POST to /v1/videos/text2video endpoint")
    func t2vPostURL() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        #expect(request.url?.absoluteString == t2vCreateURL)
    }

    @Test("text-to-video: should GET from /v1/videos/text2video/{id} for polling")
    func t2vPollURL() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 1))
        #expect(request.url?.absoluteString == t2vStatusURL)
    }

    @Test("text-to-video: should send model_name derived from model ID")
    func t2vModelName() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["model_name": .string("kling-v2-6")]))
    }

    @Test("text-to-video: should convert dots to hyphens in model_name")
    func t2vModelNameDotsToHyphens() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.1-master-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["model_name": .string("kling-v2-1-master")]))
    }

    @Test("text-to-video: should handle model IDs without dots")
    func t2vModelNameNoDots() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v1-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["model_name": .string("kling-v1")]))
    }

    @Test("text-to-video: should send prompt in request body")
    func t2vPrompt() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: "A sunset over the ocean", n: 1, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["prompt": .string("A sunset over the ocean")]))
    }

    @Test("text-to-video: should map SDK aspectRatio to aspect_ratio")
    func t2vAspectRatio() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, aspectRatio: "16:9", providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["aspect_ratio": .string("16:9")]))
        #expect(!hasUnsupportedWarning(result.warnings, feature: "aspectRatio"))
    }

    @Test("text-to-video: should map SDK duration to string")
    func t2vDuration() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, duration: 10, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["duration": .string("10")]))
        #expect(!hasUnsupportedWarning(result.warnings, feature: "duration"))
    }

    @Test("text-to-video: should send negative_prompt when provided")
    func t2vNegativePrompt() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "negativePrompt", value: .string("blurry, low quality"))

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["negative_prompt": .string("blurry, low quality")]))
    }

    @Test("text-to-video: should send sound when provided")
    func t2vSound() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "sound", value: .string("on"))

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["sound": .string("on")]))
    }

    @Test("text-to-video: should send cfg_scale when provided")
    func t2vCfgScale() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "cfgScale", value: .number(0.7))

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["cfg_scale": .number(0.7)]))
    }

    @Test("text-to-video: should send camera_control when provided")
    func t2vCameraControl() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "cameraControl", value: .object([
            "type": .string("simple"),
            "config": .object([
                "zoom": .number(5)
            ])
        ]))

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, [
            "camera_control": .object([
                "type": .string("simple"),
                "config": .object([
                    "zoom": .number(5)
                ])
            ])
        ]))
    }

    @Test("text-to-video: should derive model_name kling-v3 for kling-v3.0-t2v")
    func t2vModelNameV3() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v3.0-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: t2vProviderOptions))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["model_name": .string("kling-v3")]))
    }

    @Test("text-to-video: should send multi_shot and shot_type when provided")
    func t2vMultiShotCustomize() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "multiShot", value: .bool(true))
        setKlingAIOption(&options, key: "shotType", value: .string("customize"))
        setKlingAIOption(&options, key: "multiPrompt", value: .array([
            .object(["index": .number(1), "prompt": .string("A sunrise over mountains"), "duration": .string("4")]),
            .object(["index": .number(2), "prompt": .string("A bird flying across the sky"), "duration": .string("3")]),
        ]))

        let model = makeModel(modelId: "kling-v3.0-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, [
            "multi_shot": .bool(true),
            "shot_type": .string("customize"),
            "multi_prompt": .array([
                .object(["index": .number(1), "prompt": .string("A sunrise over mountains"), "duration": .string("4")]),
                .object(["index": .number(2), "prompt": .string("A bird flying across the sky"), "duration": .string("3")]),
            ])
        ]))
    }

    @Test("text-to-video: should send multi_shot with intelligence shot_type")
    func t2vMultiShotIntelligence() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "multiShot", value: .bool(true))
        setKlingAIOption(&options, key: "shotType", value: .string("intelligence"))

        let model = makeModel(modelId: "kling-v3.0-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        guard case .object(let dict) = body else {
            Issue.record("Expected object body")
            return
        }
        #expect(dict["multi_shot"] == .bool(true))
        #expect(dict["shot_type"] == .string("intelligence"))
        #expect(dict["multi_prompt"] == nil)
    }

    @Test("text-to-video: should send voice_list when provided for T2V")
    func t2vVoiceList() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "voiceList", value: .array([.object(["voice_id": .string("voice-abc")])]))
        setKlingAIOption(&options, key: "sound", value: .string("on"))

        let model = makeModel(modelId: "kling-v3.0-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, [
            "voice_list": .array([.object(["voice_id": .string("voice-abc")])]),
            "sound": .string("on"),
        ]))
    }

    @Test("text-to-video: should not send element_list for T2V")
    func t2vNoElementList() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = t2vProviderOptions
        setKlingAIOption(&options, key: "elementList", value: .array([.object(["element_id": .number(101)])]))

        let model = makeModel(modelId: "kling-v3.0-t2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: options))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        guard case .object(let dict) = body else {
            Issue.record("Expected object body")
            return
        }
        #expect(dict["element_list"] == nil)
    }

    @Test("text-to-video: should warn when image is provided for T2V")
    func t2vWarnOnImage() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/image.png", providerOptions: nil),
            providerOptions: t2vProviderOptions
        ))

        #expect(hasUnsupportedWarning(result.warnings, feature: "image"))
    }

    @Test("text-to-video: should return videos from successful T2V generation")
    func t2vReturnsVideos() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-t2v", fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: t2vProviderOptions))

        #expect(result.videos.first == .url(url: "https://p1.a.kwimgs.com/output/video-001.mp4", mediaType: "video/mp4"))
    }

    // MARK: - Image-to-Video

    @Test("image-to-video: should POST to /v1/videos/image2video endpoint")
    func i2vPostURL() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        #expect(request.url?.absoluteString == i2vCreateURL)
    }

    @Test("image-to-video: should GET from /v1/videos/image2video/{id} for polling")
    func i2vPollURL() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 1))
        #expect(request.url?.absoluteString == i2vStatusURL)
    }

    @Test("image-to-video: should send model_name derived from model ID")
    func i2vModelName() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["model_name": .string("kling-v2-6")]))
    }

    @Test("image-to-video: should convert dots to hyphens in I2V model_name")
    func i2vModelNameDotsToHyphens() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.5-turbo-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["model_name": .string("kling-v2-5-turbo")]))
    }

    @Test("image-to-video: should send image from URL-based input")
    func i2vImageURL() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["image": .string("https://example.com/start-frame.png")]))
    }

    @Test("image-to-video: should send image as base64 from file data")
    func i2vImageFile() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["image": .string("iVBORw==")]))
    }

    @Test("image-to-video: should send image_tail when provided")
    func i2vImageTail() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = i2vProviderOptions
        setKlingAIOption(&options, key: "imageTail", value: .string("https://example.com/end-frame.png"))

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["image_tail": .string("https://example.com/end-frame.png")]))
    }

    @Test("image-to-video: should send prompt with image")
    func i2vPrompt() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: "The cat walks away",
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["prompt": .string("The cat walks away")]))
    }

    @Test("image-to-video: should map SDK duration to string for I2V")
    func i2vDuration() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            duration: 10,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["duration": .string("10")]))
        #expect(!hasUnsupportedWarning(result.warnings, feature: "duration"))
    }

    @Test("image-to-video: should warn about aspectRatio for I2V")
    func i2vWarnAspectRatio() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            aspectRatio: "16:9",
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        #expect(hasUnsupportedWarning(result.warnings, feature: "aspectRatio"))
    }

    @Test("image-to-video: should send static_mask when provided")
    func i2vStaticMask() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = i2vProviderOptions
        setKlingAIOption(&options, key: "staticMask", value: .string("https://example.com/mask.png"))

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["static_mask": .string("https://example.com/mask.png")]))
    }

    @Test("image-to-video: should send dynamic_masks when provided")
    func i2vDynamicMasks() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let dynamicMasks: JSONValue = .array([
            .object([
                "mask": .string("https://example.com/dynamic-mask.png"),
                "trajectories": .array([
                    .object(["x": .number(279), "y": .number(219)]),
                    .object(["x": .number(417), "y": .number(65)]),
                ])
            ])
        ])

        var options = i2vProviderOptions
        setKlingAIOption(&options, key: "dynamicMasks", value: dynamicMasks)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["dynamic_masks": dynamicMasks]))
    }

    @Test("image-to-video: should derive model_name kling-v3 for kling-v3.0-i2v")
    func i2vModelNameV3() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v3.0-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["model_name": .string("kling-v3")]))
    }

    @Test("image-to-video: should send multi_shot and multi_prompt for I2V")
    func i2vMultiShotCustomize() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = i2vProviderOptions
        setKlingAIOption(&options, key: "multiShot", value: .bool(true))
        setKlingAIOption(&options, key: "shotType", value: .string("customize"))
        setKlingAIOption(&options, key: "multiPrompt", value: .array([
            .object(["index": .number(1), "prompt": .string("The cat stretches lazily"), "duration": .string("3")]),
            .object(["index": .number(2), "prompt": .string("The cat pounces on a toy"), "duration": .string("2")]),
        ]))

        let model = makeModel(modelId: "kling-v3.0-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, [
            "multi_shot": .bool(true),
            "shot_type": .string("customize"),
            "multi_prompt": .array([
                .object(["index": .number(1), "prompt": .string("The cat stretches lazily"), "duration": .string("3")]),
                .object(["index": .number(2), "prompt": .string("The cat pounces on a toy"), "duration": .string("2")]),
            ])
        ]))
    }

    @Test("image-to-video: should send element_list when provided for I2V")
    func i2vElementList() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = i2vProviderOptions
        setKlingAIOption(&options, key: "elementList", value: .array([
            .object(["element_id": .number(101)]),
            .object(["element_id": .number(202)]),
        ]))

        let model = makeModel(modelId: "kling-v3.0-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, [
            "element_list": .array([
                .object(["element_id": .number(101)]),
                .object(["element_id": .number(202)]),
            ])
        ]))
    }

    @Test("image-to-video: should send voice_list when provided for I2V")
    func i2vVoiceList() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = i2vProviderOptions
        setKlingAIOption(&options, key: "voiceList", value: .array([
            .object(["voice_id": .string("voice-abc")]),
            .object(["voice_id": .string("voice-def")]),
        ]))
        setKlingAIOption(&options, key: "sound", value: .string("on"))

        let model = makeModel(modelId: "kling-v3.0-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, [
            "voice_list": .array([
                .object(["voice_id": .string("voice-abc")]),
                .object(["voice_id": .string("voice-def")]),
            ]),
            "sound": .string("on"),
        ]))
    }

    @Test("image-to-video: should send negative_prompt for I2V")
    func i2vNegativePrompt() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        var options = i2vProviderOptions
        setKlingAIOption(&options, key: "negativePrompt", value: .string("blurry"))

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: options
        ))

        let request = try #require(await stub.request(at: 0))
        let body = try decodeRequestBody(request)
        #expect(objectContains(body, ["negative_prompt": .string("blurry")]))
    }

    @Test("image-to-video: should return videos from successful I2V generation")
    func i2vReturnsVideos() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(modelId: "kling-v2.6-i2v", fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/start-frame.png", providerOptions: nil),
            providerOptions: i2vProviderOptions
        ))

        #expect(result.videos.first == .url(url: "https://p1.a.kwimgs.com/output/video-001.mp4", mediaType: "video/mp4"))
    }

    // MARK: - Response Metadata

    @Test("response metadata includes timestamp, headers, and modelId in response")
    func responseMetadata() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let testDate = Date(timeIntervalSince1970: 1_704_067_200)
        let model = makeModel(fetch: fetch, currentDate: { testDate })
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: motionControlProviderOptions
        ))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "kling-v2.6-motion-control")
        #expect(result.response.headers != nil)
    }

    @Test("providerMetadata includes taskId and video metadata")
    func providerMetadata() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: prompt,
            n: 1,
            providerOptions: motionControlProviderOptions
        ))

        #expect(result.providerMetadata == [
            "klingai": [
                "taskId": .string("task-abc-123"),
                "videos": .array([
                    .object([
                        "id": .string("video-001"),
                        "url": .string("https://p1.a.kwimgs.com/output/video-001.mp4"),
                        "watermarkUrl": .string("https://p1.a.kwimgs.com/output/video-001-watermark.mp4"),
                        "duration": .string("5.0"),
                    ])
                ])
            ]
        ])
    }

    // MARK: - Error Handling

    @Test("error: motion control provider options are missing required fields")
    func errorMissingMotionControlFields() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [
                    "klingai": [
                        "pollIntervalMs": .number(10)
                    ]
                ]
            ))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.name == "KLINGAI_VIDEO_MISSING_OPTIONS")
        }
    }

    @Test("error: klingai provider options are missing entirely for motion control")
    func errorMissingProviderOptions() async throws {
        let stub = HTTPStub()
        try await configureDefaultSuccessResponses(stub)
        let fetch = configureFetch(stub: stub)

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [:]
            ))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message.contains("providerOptions.klingai"))
        }
    }

    @Test("error: task status is failed")
    func errorTaskFailed() async throws {
        let stub = HTTPStub()

        try await stub.setJSON(method: "POST", url: motionControlCreateURL, body: createTaskResponse)
        try await stub.setJSON(
            method: "GET",
            url: motionControlStatusURL,
            body: .object([
                "code": .number(0),
                "message": .string("success"),
                "request_id": .string("req-003"),
                "data": .object([
                    "task_id": .string("task-abc-123"),
                    "task_status": .string("failed"),
                    "task_status_msg": .string("Content policy violation"),
                    "task_info": .object([:]),
                    "created_at": .number(1_722_769_557_708),
                    "updated_at": .number(1_722_769_560_000),
                ]),
            ])
        )

        let fetch = configureFetch(stub: stub)
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: motionControlProviderOptions))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message.contains("Content policy violation"))
        }
    }

    @Test("error: no task_id is returned")
    func errorNoTaskId() async throws {
        let stub = HTTPStub()

        try await stub.setJSON(
            method: "POST",
            url: motionControlCreateURL,
            body: .object([
                "code": .number(0),
                "message": .string("success"),
                "request_id": .string("req-004"),
                "data": .null,
            ])
        )

        let fetch = configureFetch(stub: stub)
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: motionControlProviderOptions))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message.contains("No task_id"))
        }
    }

    @Test("error: no videos in response")
    func errorNoVideos() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: motionControlCreateURL, body: createTaskResponse)
        try await stub.setJSON(
            method: "GET",
            url: motionControlStatusURL,
            body: .object([
                "code": .number(0),
                "message": .string("success"),
                "request_id": .string("req-005"),
                "data": .object([
                    "task_id": .string("task-abc-123"),
                    "task_status": .string("succeed"),
                    "task_status_msg": .string(""),
                    "task_info": .object([:]),
                    "created_at": .number(1_722_769_557_708),
                    "updated_at": .number(1_722_769_560_000),
                    "task_result": .object([
                        "videos": .array([])
                    ])
                ]),
            ])
        )

        let fetch = configureFetch(stub: stub)
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: motionControlProviderOptions))
            Issue.record("Expected error")
        } catch let error as AISDKError {
            #expect(error.message.contains("No videos in response"))
        }
    }
}
