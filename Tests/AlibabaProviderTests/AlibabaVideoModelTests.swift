import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import AlibabaProvider

@Suite("AlibabaVideoModel")
struct AlibabaVideoModelTests {
    private let prompt = "A serene mountain lake at sunset with gentle ripples"
    private let baseURL = "https://dashscope-intl.aliyuncs.com"

    private var createURL: String {
        "\(baseURL)/api/v1/services/aigc/video-generation/video-synthesis"
    }

    private var taskURL: String {
        "\(baseURL)/api/v1/tasks/task-abc-123"
    }

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
            let data = try AlibabaVideoModelTests.jsonData(body)
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
                    urlResponse: AlibabaVideoModelTests.httpResponse(url: request.url!, statusCode: statusCode, headers: headerFields)
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

    private func makeModel(
        modelId: AlibabaVideoModelId = .wan26T2v,
        headers: (@Sendable () throws -> [String: String?])? = { ["Authorization": "Bearer test-api-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> AlibabaVideoModel {
        AlibabaVideoModel(
            modelId: modelId,
            config: AlibabaVideoModelConfig(
                provider: "alibaba.video",
                baseURL: baseURL,
                headers: headers ?? { [:] },
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private var defaultProviderOptions: SharedV3ProviderOptions {
        [
            "alibaba": [
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(5_000),
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

    private var createTaskResponse: [String: Any] {
        [
            "output": [
                "task_status": "PENDING",
                "task_id": "task-abc-123",
            ],
            "request_id": "req-001",
        ]
    }

    private var succeededTaskResponse: [String: Any] {
        [
            "output": [
                "task_id": "task-abc-123",
                "task_status": "SUCCEEDED",
                "video_url": "https://dashscope-result.oss.aliyuncs.com/output/video-001.mp4",
                "submit_time": "2024-01-01 00:00:00.000",
                "scheduled_time": "2024-01-01 00:00:01.000",
                "end_time": "2024-01-01 00:01:00.000",
                "orig_prompt": prompt,
                "actual_prompt": "An enhanced prompt with more cinematic details",
            ],
            "usage": [
                "duration": 5.0,
                "output_video_duration": 5,
                "SR": 1080,
                "size": "1920x1080",
            ],
            "request_id": "req-002",
        ]
    }

    @Test("constructor exposes correct provider and model information")
    func constructorInfo() throws {
        let model = makeModel()
        #expect(model.provider == "alibaba.video")
        #expect(model.modelId == "wan2.6-t2v")
        #expect(model.specificationVersion == "v3")

        switch model.maxVideosPerCall {
        case .value(let value):
            #expect(value == 1)
        case .default, .function:
            Issue.record("Expected fixed maxVideosPerCall == 1")
        }
    }

    @Test("doGenerate sends correct request body for T2V")
    func requestBodyT2V() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: defaultOptions)

        guard let call = await stub.call(at: 0) else {
            Issue.record("Missing captured request")
            return
        }

        #expect(call.url == createURL)
        #expect(call.body == .object([
            "model": .string("wan2.6-t2v"),
            "input": .object(["prompt": .string(prompt)]),
            "parameters": .object([:]),
        ]))
    }

    @Test("doGenerate sends size parameter for T2V resolution (x converted to *)")
    func t2vResolutionSizeMapping() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            resolution: "1920x1080",
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0),
              case let .object(body)? = call.body,
              case let .object(parameters)? = body["parameters"] else {
            Issue.record("Missing request body")
            return
        }

        #expect(parameters["size"] == .string("1920*1080"))
    }

    @Test("doGenerate sends provider options (negativePrompt, promptExtend, shotType, watermark)")
    func providerOptionsMapping() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "alibaba": [
                    "negativePrompt": .string("blurry, low quality"),
                    "promptExtend": .bool(true),
                    "shotType": .string("multi"),
                    "watermark": .bool(false),
                    "pollIntervalMs": .number(1),
                    "pollTimeoutMs": .number(5_000),
                ]
            ]
        ))

        guard let call = await stub.call(at: 0),
              case let .object(body)? = call.body,
              case let .object(input)? = body["input"],
              case let .object(parameters)? = body["parameters"] else {
            Issue.record("Missing request body")
            return
        }

        #expect(input["negative_prompt"] == .string("blurry, low quality"))
        #expect(parameters["prompt_extend"] == .bool(true))
        #expect(parameters["shot_type"] == .string("multi"))
        #expect(parameters["watermark"] == .bool(false))
    }

    @Test("doGenerate sends img_url from URL-based image for I2V model")
    func i2vURLImage() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(modelId: .wan26I2v, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            image: .url(url: "https://example.com/image.jpg", providerOptions: nil),
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0),
              case let .object(body)? = call.body,
              case let .object(input)? = body["input"] else {
            Issue.record("Missing request body")
            return
        }

        #expect(input["img_url"] == .string("https://example.com/image.jpg"))
    }

    @Test("doGenerate sends img_url as base64 from file data")
    func i2vFileImageBase64() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(modelId: .wan26I2vFlash, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            image: .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0),
              case let .object(body)? = call.body,
              case let .object(input)? = body["input"] else {
            Issue.record("Missing request body")
            return
        }

        #expect(input["img_url"] == .string("iVBORw=="))
    }

    @Test("maps resolution to I2V format (WxH → 720P/1080P)")
    func i2vResolutionMapping() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(modelId: .wan26I2v, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            resolution: "1920x1080",
            providerOptions: defaultProviderOptions
        ))

        guard let call = await stub.call(at: 0),
              case let .object(body)? = call.body,
              case let .object(parameters)? = body["parameters"] else {
            Issue.record("Missing request body")
            return
        }

        #expect(parameters["resolution"] == .string("1080P"))
    }

    @Test("sends reference_urls for R2V model and does not for other modes")
    func r2vReferenceURLs() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(modelId: .wan26R2vFlash, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "alibaba": [
                    "referenceUrls": .array([
                        .string("https://example.com/ref-image.jpg"),
                        .string("https://example.com/ref-video.mp4"),
                    ]),
                    "pollIntervalMs": .number(1),
                    "pollTimeoutMs": .number(5_000),
                ]
            ]
        ))

        guard let call = await stub.call(at: 0),
              case let .object(body)? = call.body,
              case let .object(input)? = body["input"] else {
            Issue.record("Missing request body")
            return
        }

        #expect(input["reference_urls"] == .array([
            .string("https://example.com/ref-image.jpg"),
            .string("https://example.com/ref-video.mp4"),
        ]))
    }

    @Test("sends X-DashScope-Async only on task creation")
    func headersAsyncOnlyOnCreate() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: defaultOptions)

        guard let createCall = await stub.call(at: 0), let pollCall = await stub.call(at: 1) else {
            Issue.record("Missing captured calls")
            return
        }

        #expect(createCall.headers["x-dashscope-async"] == "enable")
        #expect(pollCall.headers["x-dashscope-async"] == nil)
    }

    @Test("warns for unsupported aspectRatio/fps/n")
    func warningsUnsupported() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 3,
            aspectRatio: "16:9",
            fps: 30,
            providerOptions: defaultProviderOptions
        ))

        #expect(result.warnings.contains(.unsupported(feature: "aspectRatio", details: "Alibaba video models use explicit size/resolution dimensions. Use the resolution option or providerOptions.alibaba for size control.")))
        #expect(result.warnings.contains(.unsupported(feature: "fps", details: "Alibaba video models do not support custom FPS.")))
        #expect(result.warnings.contains(.unsupported(feature: "n", details: "Alibaba video models only support generating 1 video per call.")))
    }

    @Test("returns video URL, response info, and provider metadata")
    func responseAndMetadata() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let testDate = Date(timeIntervalSince1970: 1_704_067_200)
        let model = makeModel(fetch: fetch, currentDate: { testDate })

        let result = try await model.doGenerate(options: defaultOptions)

        #expect(result.videos == [.url(
            url: "https://dashscope-result.oss.aliyuncs.com/output/video-001.mp4",
            mediaType: "video/mp4"
        )])
        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "wan2.6-t2v")

        #expect(result.providerMetadata?["alibaba"] == [
            "taskId": .string("task-abc-123"),
            "videoUrl": .string("https://dashscope-result.oss.aliyuncs.com/output/video-001.mp4"),
            "actualPrompt": .string("An enhanced prompt with more cinematic details"),
            "usage": .object([
                "duration": .number(5),
                "outputVideoDuration": .number(5),
                "resolution": .number(1080),
                "size": .string("1920x1080"),
            ]),
        ])
    }

    @Test("throws when no task_id is returned")
    func errorNoTaskId() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: ["output": NSNull(), "request_id": "req-003"])
        try await stub.setJSON(method: "GET", url: taskURL, body: succeededTaskResponse)

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("No task_id"))
        }
    }

    @Test("throws when task status is FAILED")
    func errorFailedStatus() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: [
            "output": [
                "task_id": "task-abc-123",
                "task_status": "FAILED",
                "message": "Content policy violation",
            ],
            "request_id": "req-004",
        ])

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("failed"))
        }
    }

    @Test("throws when task status is CANCELED")
    func errorCanceledStatus() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: [
            "output": [
                "task_id": "task-abc-123",
                "task_status": "CANCELED",
            ],
            "request_id": "req-005",
        ])

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("canceled"))
        }
    }

    @Test("throws when no video URL in succeeded response")
    func errorNoVideoURL() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)
        try await stub.setJSON(method: "GET", url: taskURL, body: [
            "output": [
                "task_id": "task-abc-123",
                "task_status": "SUCCEEDED",
                "video_url": NSNull(),
            ],
            "request_id": "req-006",
        ])

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: defaultOptions)
            Issue.record("Expected error")
        } catch {
            #expect(String(describing: error).localizedCaseInsensitiveContains("No video URL"))
        }
    }

    @Test("polls until SUCCEEDED status")
    func pollingUntilSucceeded() async throws {
        let stub = HTTPStub()
        try await stub.setJSON(method: "POST", url: createURL, body: createTaskResponse)

        await stub.setHandler(method: "GET", url: taskURL) { request, callNumber in
            let body: Any
            if callNumber < 3 {
                body = [
                    "output": [
                        "task_id": "task-abc-123",
                        "task_status": callNumber == 1 ? "PENDING" : "RUNNING",
                    ],
                    "request_id": "req-poll-\(callNumber)",
                ]
            } else {
                body = self.succeededTaskResponse
            }

            let data = try AlibabaVideoModelTests.jsonData(body)
            return FetchResponse(
                body: .data(data),
                urlResponse: AlibabaVideoModelTests.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
            )
        }

        let fetch: FetchFunction = { request in try await stub.handle(request) }
        let model = makeModel(fetch: fetch)

        let result = try await model.doGenerate(options: defaultOptions)
        #expect(result.videos.count == 1)
    }
}
