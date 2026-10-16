import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ByteDanceProvider

@Suite("ByteDance video V4 operations")
struct ByteDanceVideoModelTests {
    private let baseURL = "https://api.example.com/v3"
    private let date = Date(timeIntervalSince1970: 1_704_067_200)
    private var operation: JSONValue { .object(["taskId": .string("job")]) }

    private actor Capture {
        var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
        func first() -> URLRequest? { requests.first }
    }

    private func response(_ request: URLRequest, status: Int = 200, body: String) -> FetchResponse {
        .init(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "x-request-id": "response-id"]
        )!)
    }

    private func model(fetch: @escaping FetchFunction) -> ByteDanceVideoModel {
        ByteDanceVideoModel(modelId: .seedance15Pro251215, config: .init(
            provider: "bytedance.video", baseURL: baseURL, headers: { ["Authorization": "Bearer key"] },
            fetch: fetch, currentDate: { date }
        ))
    }

    private func body(_ request: URLRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    }

    @Test("start serializes generation settings and provider options with callback precedence")
    func startRequest() async throws {
        let capture = Capture()
        let provider = createByteDance(settings: .init(apiKey: "secret", baseURL: baseURL + "/",
                                                      headers: ["x-provider": "provider"], fetch: { request in
            await capture.record(request)
            return response(request, body: #"{"id":"job"}"#)
        }))
        let result = try await provider.video(.seedance15Pro251215).doStart(options: .init(
            prompt: "city", n: 2, aspectRatio: "16:9", resolution: "1920x1080", duration: 5, fps: 30, seed: 42,
            generateAudio: false, providerOptions: ["bytedance": [
                "watermark": .bool(false), "generateAudio": .bool(true), "cameraFixed": .bool(true),
                "returnLastFrame": .bool(true), "serviceTier": .string("flex"), "draft": .bool(false),
                "pollIntervalMs": .number(1), "pollTimeoutMs": .number(2), "custom": .null,
                "callback_url": .string("ignored"),
            ]], headers: ["x-client": "client"]
        ), webhookUrl: "https://example.com/callback")
        let request = try #require(await capture.first())
        #expect(request.url?.absoluteString == baseURL + "/contents/generations/tasks")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "x-provider") == "provider")
        #expect(request.value(forHTTPHeaderField: "x-client") == "client")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-bytedance/") == true)
        #expect(try body(request) == .object([
            "model": .string("seedance-1-5-pro-251215"), "content": .array([.object(["type": .string("text"), "text": .string("city")])]),
            "ratio": .string("16:9"), "resolution": .string("1080p"), "duration": .number(5), "seed": .number(42),
            "generate_audio": .bool(false), "watermark": .bool(false), "camera_fixed": .bool(true), "return_last_frame": .bool(true),
            "service_tier": .string("flex"), "draft": .bool(false), "custom": .null, "callback_url": .string("https://example.com/callback"),
        ]))
        #expect(result.operation == operation)
        #expect(result.response.headers?["x-request-id"] == "response-id")
        #expect(result.warnings.contains { if case .deprecated(setting: "pollIntervalMs", _) = $0 { true } else { false } })
        #expect(result.warnings.contains { if case .deprecated(setting: "pollTimeoutMs", _) = $0 { true } else { false } })
        #expect(result.warnings.contains { if case .unsupported(feature: "fps", _) = $0 { true } else { false } })
        #expect(result.warnings.contains { if case .unsupported(feature: "n", _) = $0 { true } else { false } })
    }

    @Test("frames override the start and end image and suppress all image/video references")
    func framePrecedence() async throws {
        let capture = Capture()
        let model = model { request in
            await capture.record(request)
            return response(request, body: #"{"id":"job"}"#)
        }
        _ = try await model.doStart(options: .init(n: 1,
            image: .url(url: "https://example.com/ignored", providerOptions: nil),
            frameImages: [
                .init(image: .file(mediaType: "image/png", data: .base64("AQID"), providerOptions: nil), frameType: .firstFrame),
                .init(image: .url(url: "https://example.com/last", providerOptions: nil), frameType: .lastFrame),
            ], inputReferences: [.url(url: "https://example.com/ignored-reference", providerOptions: nil)],
            providerOptions: ["bytedance": [
                "lastFrameImage": .string("ignored"), "referenceImages": .array([.string("ignored")]),
                "referenceVideos": .array([.string("ignored")]), "referenceAudio": .array([.string("https://example.com/audio")]),
            ]]
        ))
        let request = try #require(await capture.first())
        #expect(try body(request) == .object([
            "model": .string("seedance-1-5-pro-251215"), "content": .array([
                .object(["type": .string("image_url"), "image_url": .object(["url": .string("data:image/png;base64,AQID")]), "role": .string("first_frame")]),
                .object(["type": .string("image_url"), "image_url": .object(["url": .string("https://example.com/last")]), "role": .string("last_frame")]),
                .object(["type": .string("audio_url"), "audio_url": .object(["url": .string("https://example.com/audio")]), "role": .string("reference_audio")]),
            ]),
        ]))
    }

    @Test("standard references route media types and override legacy reference arrays")
    func referenceRouting() async throws {
        let capture = Capture()
        let model = model { request in
            await capture.record(request)
            return response(request, body: #"{"id":"job"}"#)
        }
        let result = try await model.doStart(options: .init(n: 1,
            image: .url(url: "https://example.com/start", providerOptions: nil),
            inputReferences: [
                .url(url: "https://example.com/video", mediaType: "video/mp4", providerOptions: nil),
                .file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil),
                .url(url: "https://example.com/unknown", providerOptions: nil),
            ], providerOptions: ["bytedance": ["referenceImages": .array([.string("ignored")])]]
        ))
        let request = try #require(await capture.first())
        guard case .object(let value) = try body(request), case .array(let content) = value["content"] else {
            Issue.record("Expected content array")
            return
        }
        #expect(content == [
            .object(["type": .string("image_url"), "image_url": .object(["url": .string("https://example.com/start")]), "role": .string("reference_image")]),
            .object(["type": .string("video_url"), "video_url": .object(["url": .string("https://example.com/video")]), "role": .string("reference_video")]),
            .object(["type": .string("image_url"), "image_url": .object(["url": .string("data:image/png;base64,AQID")]), "role": .string("reference_image")]),
            .object(["type": .string("image_url"), "image_url": .object(["url": .string("https://example.com/unknown")]), "role": .string("reference_image")]),
        ])
        #expect(result.warnings.contains { if case .unsupported(feature: "inputReferences", _) = $0 { true } else { false } })
    }

    @Test("legacy reference inputs remain available and zero-valued settings are omitted")
    func legacyInputs() async throws {
        let capture = Capture()
        let model = model { request in
            await capture.record(request)
            return response(request, body: #"{"id":"job"}"#)
        }
        let result = try await model.doStart(options: .init(n: 1, duration: 0, fps: 0, seed: 0,
            image: .url(url: "start", providerOptions: nil), providerOptions: ["bytedance": [
                "lastFrameImage": .string("last"), "referenceImages": .array([.string("image")]),
                "referenceVideos": .array([.string("video")]), "generateAudio": .bool(true),
            ]]
        ))
        let request = try #require(await capture.first())
        #expect(try body(request) == .object([
            "model": .string("seedance-1-5-pro-251215"), "generate_audio": .bool(true), "content": .array([
                .object(["type": .string("image_url"), "image_url": .object(["url": .string("start")]), "role": .string("first_frame")]),
                .object(["type": .string("image_url"), "image_url": .object(["url": .string("last")]), "role": .string("last_frame")]),
                .object(["type": .string("image_url"), "image_url": .object(["url": .string("image")]), "role": .string("reference_image")]),
                .object(["type": .string("video_url"), "video_url": .object(["url": .string("video")]), "role": .string("reference_video")]),
            ]),
        ]))
        #expect(result.warnings.isEmpty)
    }

    @Test("known pixel resolutions map to API levels", arguments: ["864x496", "1280x720", "1920x1080", "custom"])
    func resolutionMapping(resolution: String) async throws {
        let capture = Capture()
        let model = model { request in
            await capture.record(request)
            return response(request, body: #"{"id":"job"}"#)
        }
        _ = try await model.doStart(options: .init(n: 1, resolution: resolution))
        let request = try #require(await capture.first())
        let expected = ["864x496": "480p", "1280x720": "720p", "1920x1080": "1080p"][resolution] ?? resolution
        guard case .object(let value) = try body(request) else { Issue.record("Expected body object"); return }
        #expect(value["resolution"] == .string(expected))
    }

    @Test("status completes with URL, nullable usage and last-frame metadata")
    func completedStatus() async throws {
        let model = model { request in
            #expect(request.url?.absoluteString == baseURL + "/contents/generations/tasks/job")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            return response(request, body: #"{"status":"succeeded","content":{"video_url":"https://cdn.example.net/video.mp4","last_frame_url":"https://cdn.example.net/last.png"},"usage":{"completion_tokens":null,"extra":1}}"#)
        }
        guard case .completed(let videos, let warnings, let metadata, let info) = try await model.doStatus(options: .init(operation: operation)) else {
            Issue.record("Expected completed status"); return
        }
        #expect(videos == [.url(url: "https://cdn.example.net/video.mp4", mediaType: "video/mp4")])
        #expect(warnings.isEmpty)
        #expect(metadata?["bytedance"] == ["taskId": .string("job"), "usage": .object(["completion_tokens": .null]), "lastFrameUrl": .string("https://cdn.example.net/last.png")])
        #expect(info.timestamp == date)
        #expect(info.headers?["x-request-id"] == "response-id")
    }

    @Test("nonterminal statuses stay pending", arguments: ["queued", "running", "unknown"])
    func pendingStatus(status: String) async throws {
        let model = model { request in response(request, body: #"{"status":"\#(status)"}"#) }
        guard case .pending(_, _, let info) = try await model.doStatus(options: .init(operation: operation)) else {
            Issue.record("Expected pending status"); return
        }
        #expect(info.timestamp == date)
        #expect(info.headers?["x-request-id"] == "response-id")
    }

    @Test("all terminal failure statuses return actionable error state", arguments: ["failed", "expired", "cancelled", "canceled"])
    func failedStatus(status: String) async throws {
        let model = model { request in response(request, body: #"{"status":"\#(status)","error":{"message":"blocked","code":"Denied"}}"#) }
        guard case .error(let message, _, let info) = try await model.doStatus(options: .init(operation: operation)) else {
            Issue.record("Expected error status"); return
        }
        #expect(message == "Video generation \(status). Task ID: job. blocked")
        #expect(info.headers?["x-request-id"] == "response-id")
    }

    @Test("failure diagnostics fall back from message to code and then parsed task data", arguments: [false, true])
    func failureDetails(code: Bool) async throws {
        let model = model { request in response(request, body: code ? #"{"status":"failed","error":{"code":"Denied"}}"# : #"{"status":"failed","extra":"ignored"}"#) }
        guard case .error(let message, _, _) = try await model.doStatus(options: .init(operation: operation)) else {
            Issue.record("Expected error status"); return
        }
        #expect(message == "Video generation failed. Task ID: job. " + (code ? "Denied" : #"{"status":"failed"}"#))
    }

    @Test("missing task IDs and successful tasks without video URLs remain generation errors", arguments: [false, true])
    func missingRequiredOutput(status: Bool) async throws {
        let model = model { request in response(request, body: status ? #"{"status":"succeeded"}"# : "{}") }
        do {
            if status { _ = try await model.doStatus(options: .init(operation: operation)) }
            else { _ = try await model.doStart(options: .init(n: 1)) }
            Issue.record("Expected generation error")
        } catch let error as any AISDKError {
            #expect(error.name == "BYTEDANCE_VIDEO_GENERATION_ERROR")
            #expect(error.message == (status ? "No video URL in response. Task ID: job" : "No task ID returned from API"))
        }
    }

    @Test("API failures from start and status remain thrown HTTP errors", arguments: [false, true])
    func apiErrors(status: Bool) async throws {
        let model = model { request in response(request, status: 429, body: #"{"error":{"message":"quota","code":null}}"#) }
        do {
            if status { _ = try await model.doStatus(options: .init(operation: operation)) }
            else { _ = try await model.doStart(options: .init(n: 1)) }
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "quota")
            #expect(error.statusCode == 429)
            #expect(error.isRetryable)
        }
    }

    @Test("invalid provider options fail before submission")
    func invalidOptions() async throws {
        let model = model { _ in throw CancellationError() }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doStart(options: .init(n: 1, providerOptions: ["bytedance": ["pollIntervalMs": .number(0)]]))
        }
    }

    @Test("cancellation passes through without a provider error wrapper")
    func cancellation() async throws {
        let model = model { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) { _ = try await model.doStart(options: .init(n: 1, abortSignal: { true })) }
        await #expect(throws: CancellationError.self) { _ = try await model.doStatus(options: .init(operation: operation, abortSignal: { true })) }
    }
}
