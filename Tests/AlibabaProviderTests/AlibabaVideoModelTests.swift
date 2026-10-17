import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import AlibabaProvider

@Suite("Alibaba video V4 operations")
struct AlibabaVideoModelTests {
    private static let baseURL = "https://proxy.example"
    private static let createPath = "/api/v1/services/aigc/video-generation/video-synthesis"
    private static let taskPath = "/api/v1/tasks/task-id"
    private static let created: JSONValue = ["output": ["task_status": "PENDING", "task_id": "task-id"], "request_id": "created-request"]
    private static let date = Date(timeIntervalSince1970: 123)

    private actor Endpoint {
        var payload: JSONValue
        var status: Int
        let inspect: @Sendable (URLRequest) throws -> Void
        init(_ payload: JSONValue = AlibabaVideoModelTests.created, status: Int = 200, inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) {
            self.payload = payload
            self.status = status
            self.inspect = inspect
        }
        func set(_ value: JSONValue) { payload = value }
        func fetch(_ request: URLRequest) throws -> FetchResponse {
            try inspect(request)
            return FetchResponse(body: .data(try JSONEncoder().encode(payload)), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Response": "response-id"]
            )!)
        }
    }

    private func model(_ id: AlibabaVideoModelId = .wan26T2v, endpoint: Endpoint) -> AlibabaVideoModel {
        AlibabaVideoModel(modelId: id, config: .init(
            provider: "alibaba.video", baseURL: Self.baseURL,
            headers: { ["Authorization": "Bearer provider-key", "X-Provider": "account", "User-Agent": "ai-sdk-alibaba/test"] },
            fetch: { try await endpoint.fetch($0) }, currentDate: { Self.date }
        ))
    }

    private func body(_ request: URLRequest) throws -> JSONObject {
        try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
    }

    @Test("model versions select the size, tiered-reference or all-in-one wire protocol", arguments: [
        "wanx2.1-t2v-turbo", "wan2.6-r2v", "wan2.7-r2v", "wan2.10-r2v", "wan3.0-video", "wan-next-video"
    ])
    func protocolRouting(id: String) async throws {
        let sized = id == "wanx2.1-t2v-turbo" || id == "wan2.6-r2v"
        let allInOne = id == "wan3.0-video" || id == "wan-next-video"
        var input: JSONObject = ["prompt": "A scene"]
        if id == "wan2.6-r2v" { input["reference_urls"] = ["https://media.example/ref.png"] }
        else if id != "wanx2.1-t2v-turbo" {
            var media: [JSONValue] = [["type": "reference_image", "url": "https://media.example/ref.png"]]
            if allInOne { media.append(["type": "first_frame", "url": "https://media.example/start.png"]) }
            input["media"] = .array(media)
        }
        let expected: JSONObject = [
            "model": .string(id), "input": .object(input),
            "parameters": sized ? ["size": "1280*720"] : ["resolution": "720P", "ratio": "16:9"]
        ]
        let endpoint = Endpoint { (request: URLRequest) throws -> Void in
            #expect(request.url?.path == Self.createPath)
            #expect(request.httpMethod == "POST")
            #expect(try body(request) == expected)
        }
        let result = try await model(.init(rawValue: id), endpoint: endpoint).doStart(options: .init(
            prompt: "A scene", n: 1, resolution: "1280x720",
            image: .url(url: "https://media.example/start.png", providerOptions: nil),
            inputReferences: [.url(url: "https://media.example/ref.png", providerOptions: nil)]
        ))
        #expect(result.operation == ["taskId": "task-id"])
        #expect(result.warnings.map(feature) == (id == "wanx2.1-t2v-turbo" ? ["inputReferences"] : []))
    }

    @Test("image models prefer first-frame bytes and retain protocol-specific parameter rules", arguments: [false, true])
    func imageProtocol(tiered: Bool) async throws {
        let id = tiered ? "wan2.7-i2v" : "wan2.6-i2v"
        let parameters: JSONValue = tiered ? [:] : ["resolution": "480P", "shot_type": "multi", "audio": false]
        let endpoint = Endpoint { (request: URLRequest) throws -> Void in
            #expect(try body(request) == ["model": .string(id), "input": ["img_url": "iVBORw=="], "parameters": parameters])
        }
        let result = try await model(.init(rawValue: id), endpoint: endpoint).doStart(options: .init(
            n: 1, aspectRatio: "9:16", resolution: "832x480", image: .url(url: "https://media.example/ignored.png", providerOptions: nil),
            frameImages: [
                .init(image: .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil), frameType: .firstFrame),
                .init(image: .url(url: "https://media.example/end.png", providerOptions: nil), frameType: .lastFrame)
            ],
            generateAudio: false, providerOptions: ["alibaba": ["shotType": "multi", "audio": true]]
        ))
        #expect(result.warnings.map(feature) == (tiered ? ["frameImages", "resolution", "shotType", "generateAudio", "aspectRatio"] : ["frameImages", "aspectRatio"]))
    }

    @Test("all-in-one requests combine typed references, frames, audio and smart duration")
    func allInOneMedia() async throws {
        let expected: JSONObject = [
            "model": "wan3.0-video",
            "input": ["prompt": "A scene", "negative_prompt": "blur", "audio_url": "https://media.example/audio.mp3", "media": [
                ["type": "reference_image", "url": "data:image/png;base64,iVBORw=="],
                ["type": "reference_video", "url": "https://media.example/clip.MOV?token=one"],
                ["type": "first_frame", "url": "data:image/jpeg;base64,AQID"],
                ["type": "last_frame", "url": "https://media.example/end.png"]
            ]],
            "parameters": ["duration": -1, "seed": 7, "resolution": "480P", "ratio": "adaptive", "prompt_extend": false, "watermark": true, "audio": false]
        ]
        let endpoint = Endpoint { (request: URLRequest) throws -> Void in #expect(try body(request) == expected) }
        let result = try await model(.wan30Video, endpoint: endpoint).doStart(options: .init(
            prompt: "A scene", n: 3, aspectRatio: "9:16", resolution: "832x480", duration: -1, fps: 24, seed: 7,
            frameImages: [
                .init(image: .file(mediaType: "image/jpeg", data: .base64("AQID"), providerOptions: nil), frameType: .firstFrame),
                .init(image: .url(url: "https://media.example/end.png", providerOptions: nil), frameType: .lastFrame)
            ],
            inputReferences: [
                .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
                .url(url: "https://media.example/clip.MOV?token=one", mediaType: "image/jpeg", providerOptions: nil),
                .file(mediaType: "video/mp4", data: .base64("AAAA"), providerOptions: nil)
            ],
            generateAudio: false,
            providerOptions: ["alibaba": ["ratio": "adaptive", "audio": true, "shotType": "multi", "negativePrompt": "blur", "audioUrl": "https://media.example/audio.mp3", "promptExtend": false, "watermark": true]]
        ))
        #expect(result.warnings.map(feature) == ["inputReferences", "shotType", "fps", "n"])
    }

    @Test("explicit media overrides automatic inputs and carries wan3 media kinds and voice references")
    func explicitMedia() async throws {
        let media: [JSONValue] = [
            ["type": "reference_audio", "url": "https://media.example/voice.mp3", "referenceVoice": .null],
            ["type": "file", "url": "https://media.example/deck.pdf"],
            ["type": "link", "url": "https://example.com/article"],
            ["type": "reference_video", "url": "https://media.example/ref.mp4", "referenceVoice": "https://media.example/voice.mp3", "extra": true],
            ["type": "last_frame", "url": "https://media.example/end.png"]
        ]
        let endpoint = Endpoint { (request: URLRequest) throws -> Void in
            #expect(try body(request) == ["model": "wan3.0-video", "input": ["media": [
                ["type": "reference_audio", "url": "https://media.example/voice.mp3"],
                ["type": "file", "url": "https://media.example/deck.pdf"],
                ["type": "link", "url": "https://example.com/article"],
                ["type": "reference_video", "url": "https://media.example/ref.mp4", "reference_voice": "https://media.example/voice.mp3"],
                ["type": "last_frame", "url": "https://media.example/end.png"]
            ]], "parameters": ["resolution": "1080P", "ratio": "1:1"]])
        }
        let result = try await model(.wan30Video, endpoint: endpoint).doStart(options: .init(
            n: 1, aspectRatio: "16:9", resolution: "1920x1080", image: .url(url: "ignored", providerOptions: nil),
            inputReferences: [.file(mediaType: "video/mp4", data: .base64("AAAA"), providerOptions: nil)],
            providerOptions: ["alibaba": ["media": .array(media), "ratio": "1:1", "future": true]]
        ))
        #expect(result.warnings.isEmpty)
    }

    @Test("size-protocol references honor standard options, provider fallback and frame exclusions", arguments: ["standard", "provider", "frames"])
    func referencePriority(source: String) async throws {
        let frames = source == "frames"
        let provider = source == "provider"
        let endpoint = Endpoint { (request: URLRequest) throws -> Void in
            let input: JSONValue = frames ? [:] : ["reference_urls": [.string(provider ? "https://media.example/fallback.png" : "https://media.example/standard.png")]]
            #expect(try body(request) == ["model": "wan2.6-r2v", "input": input, "parameters": [:]])
        }
        let result = try await model(.wan26R2v, endpoint: endpoint).doStart(options: .init(
            n: 1, frameImages: frames ? [.init(image: .url(url: "https://media.example/end.png", providerOptions: nil), frameType: .lastFrame)] : nil,
            inputReferences: provider ? nil : [.url(url: "https://media.example/standard.png", providerOptions: nil), .file(mediaType: "image/png", data: .base64("AAAA"), providerOptions: nil)],
            providerOptions: ["alibaba": ["referenceUrls": ["https://media.example/fallback.png"]]]
        ))
        #expect(result.warnings.map(feature) == (provider ? [] : [frames ? "frameImages" : "inputReferences"]))
    }

    @Test("start and resumed status calls preserve operation IDs, API headers and response metadata")
    func resumableOperation() async throws {
        let endpoint = Endpoint { (request: URLRequest) throws -> Void in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer caller-key")
            #expect(request.value(forHTTPHeaderField: "X-Provider") == "account")
            #expect(request.value(forHTTPHeaderField: "X-Request") == "caller")
            if request.httpMethod == "POST" {
                #expect(request.url?.path == Self.createPath)
                #expect(request.value(forHTTPHeaderField: "X-DashScope-Async") == "enable")
            } else {
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == Self.taskPath)
            }
        }
        let headers = ["authorization": "Bearer caller-key", "X-Request": "caller"]
        let started = try await model(.wan30Video, endpoint: endpoint).doStart(options: .init(n: 1, headers: headers))
        let operation = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(started.operation))
        #expect(operation == ["taskId": "task-id"])
        #expect(started.response.timestamp == Self.date)
        #expect(started.response.headers?["x-response"] == "response-id")
        let resumed = model(.wan30Video, endpoint: endpoint)
        await endpoint.set(["output": ["task_id": "task-id", "task_status": "RUNNING"]])
        guard case .pending(_, _, let pendingInfo) = try await resumed.doStatus(options: .init(operation: operation, headers: headers)) else {
            Issue.record("Expected pending operation"); return
        }
        #expect(pendingInfo.modelId == "wan3.0-video")
        await endpoint.set([
            "output": ["task_id": "task-id", "task_status": "SUCCEEDED", "video_url": "https://proxy.example/result.mp4", "actual_prompt": "Expanded scene"],
            "usage": ["duration": 12.5, "output_video_duration": 8.5, "input_video_duration": 4, "fps": .number(1e100), "SR": 720, "size": "1280x720", "ratio": "16:9"]
        ])
        guard case .completed(let videos, let warnings, let metadata, let response) = try await resumed.doStatus(options: .init(operation: operation, headers: headers)) else {
            Issue.record("Expected completed operation"); return
        }
        #expect(videos == [.url(url: "https://proxy.example/result.mp4", mediaType: "video/mp4")])
        #expect(warnings.isEmpty)
        #expect(metadata == ["alibaba": ["taskId": "task-id", "videoUrl": "https://proxy.example/result.mp4", "actualPrompt": "Expanded scene", "usage": ["duration": 12.5, "outputVideoDuration": 8.5, "inputVideoDuration": 4, "fps": .number(1e100), "resolution": 720, "size": "1280x720", "ratio": "16:9"]]])
        #expect(response.timestamp == Self.date)
        #expect(response.headers?["x-response"] == "response-id")
    }

    @Test("completed metadata preserves nullable base usage and omits null wan3-only facts")
    func nullableUsage() async throws {
        let endpoint = Endpoint([
            "output": ["task_id": "task-id", "task_status": "SUCCEEDED", "video_url": "https://media.example/result.mp4"],
            "usage": ["duration": .null, "output_video_duration": 1.5, "SR": .null, "size": .null, "input_video_duration": .null, "fps": .null, "ratio": .null]
        ])
        guard case .completed(_, _, let metadata, _) = try await model(endpoint: endpoint).doStatus(options: .init(operation: ["taskId": "task-id"])) else {
            Issue.record("Expected completed operation"); return
        }
        #expect(metadata?["alibaba"]?["usage"] == ["duration": .null, "outputVideoDuration": 1.5, "resolution": .null, "size": .null])
    }

    @Test("failed and canceled operations return terminal errors with response diagnostics", arguments: ["FAILED", "CANCELED"])
    func failedOperation(status: String) async throws {
        let endpoint = Endpoint(["output": ["task_id": "task-id", "task_status": .string(status), "message": "Policy decision \u{FEFF}"]])
        guard case .error(let error, let metadata, let response) = try await model(endpoint: endpoint).doStatus(options: .init(operation: ["taskId": "task-id"])) else {
            Issue.record("Expected terminal error"); return
        }
        #expect(error == "Video generation \(status.lowercased()). Task ID: task-id. Policy decision")
        #expect(metadata == nil)
        #expect(response.timestamp == Self.date)
        #expect(response.modelId == "wan2.6-t2v")
    }

    @Test("unknown task statuses and null outputs remain pending", arguments: [JSONValue.null, ["task_id": "task-id", "task_status": "NEW_STATUS"]])
    func pendingOperation(output: JSONValue) async throws {
        let endpoint = Endpoint(["output": output])
        guard case .pending = try await model(endpoint: endpoint).doStatus(options: .init(operation: ["taskId": "task-id"])) else {
            Issue.record("Expected pending operation"); return
        }
    }

    @Test("missing creation ID or completed URL yields the provider generation error", arguments: [false, true])
    func missingResult(status: Bool) async throws {
        let payload: JSONValue = status ? ["output": ["task_id": "task-id", "task_status": "SUCCEEDED", "video_url": .null]] : ["output": .null, "request_id": "request-id"]
        let instance = model(endpoint: Endpoint(payload))
        do {
            if status { _ = try await instance.doStatus(options: .init(operation: ["taskId": "task-id"])) }
            else { _ = try await instance.doStart(options: .init(n: 1)) }
            Issue.record("Expected generation error")
        } catch let error as any AISDKError {
            #expect(error.name == "ALIBABA_VIDEO_GENERATION_ERROR")
            #expect(hasMarker(error, marker: "vercel.ai.error"))
            #expect(error.message.contains(status ? "No video URL" : "No task_id"))
        }
    }

    @Test("native API error bodies retain status, provider message and headers", arguments: [false, true])
    func apiError(status: Bool) async throws {
        let endpoint = Endpoint(["code": .null, "message": "Denied", "request_id": .null], status: 401)
        let instance = model(endpoint: endpoint)
        do {
            if status { _ = try await instance.doStatus(options: .init(operation: ["taskId": "task-id"])) }
            else { _ = try await instance.doStart(options: .init(n: 1)) }
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.statusCode == 401)
            #expect(error.message == "Denied")
            #expect(!error.isRetryable)
            #expect(error.responseHeaders?["x-response"] == "response-id")
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(#require(error.responseBody).utf8)) == ["code": .null, "message": "Denied", "request_id": .null])
        }
    }

    @Test("task wire types validate required IDs and numeric usage", arguments: [false, true])
    func invalidResponse(status: Bool) async throws {
        let payload: JSONValue = status ? ["output": ["task_id": "task-id", "task_status": "SUCCEEDED"], "usage": ["fps": "24"]] : ["output": ["task_id": "task-id"]]
        let instance = model(endpoint: Endpoint(payload))
        await #expect(throws: APICallError.self) {
            if status { _ = try await instance.doStatus(options: .init(operation: ["taskId": "task-id"])) }
            else { _ = try await instance.doStart(options: .init(n: 1)) }
        }
    }

    @Test("video option schemas reject unsupported kinds, invalid ratios and nonpositive intervals", arguments: [
        ["media": [["type": "unknown", "url": "url"]]] as JSONObject, ["ratio": "2:1"], ["pollIntervalMs": 0], ["audio": "false"]
    ])
    func invalidOptions(settings: JSONObject) async throws {
        await #expect(throws: InvalidArgumentError.self) {
            try await model(endpoint: Endpoint()).doStart(options: .init(n: 1, providerOptions: ["alibaba": settings]))
        }
    }

    @Test("nullish video options and fractional polling settings retain source defaults")
    func nullishOptions() async throws {
        let endpoint = Endpoint { (request: URLRequest) throws -> Void in #expect(try body(request) == ["model": "wan2.6-t2v", "input": [:], "parameters": [:]]) }
        let result = try await model(endpoint: endpoint).doStart(options: .init(n: 1, fps: 0, providerOptions: ["alibaba": [
            "negativePrompt": .null, "audioUrl": .null, "promptExtend": .null, "shotType": .null, "watermark": .null, "audio": .null,
            "referenceUrls": .null, "media": .null, "ratio": .null, "pollIntervalMs": 0.5, "pollTimeoutMs": .number(1e100), "future": ["kept": true]
        ]]))
        #expect(result.operation == ["taskId": "task-id"])
        #expect(result.warnings.isEmpty)
    }

    @Test("start and status honor aborted requests", arguments: [false, true])
    func cancellation(status: Bool) async throws {
        let instance = model(endpoint: Endpoint())
        await #expect(throws: CancellationError.self) {
            if status { _ = try await instance.doStatus(options: .init(operation: ["taskId": "task-id"], abortSignal: { true })) }
            else { _ = try await instance.doStart(options: .init(n: 1, abortSignal: { true })) }
        }
    }
}

private func feature(_ warning: SharedV4Warning) -> String {
    if case .unsupported(let feature, _) = warning { return feature }
    return "other"
}
