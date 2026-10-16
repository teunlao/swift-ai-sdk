import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import XAIProvider

@Suite("XAIVideoModel")
struct XAIVideoModelTests {
    private actor Capture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func last() -> URLRequest? { requests.last }
    }
    private func model(_ payload: String = #"{"request_id":"req-123"}"#, status: Int = 200, modelId: XAIVideoModelId = .grokImagineVideo, capture: Capture = Capture()) -> XAIVideoModel {
        XAIVideoModel(modelId: modelId, config: .init(provider: "xai.video", baseURL: "https://api.example.com", headers: { ["Authorization": "Bearer key", "X-Provider": "provider"] }, fetch: { request in
            await capture.append(request)
            return FetchResponse(body: .data(Data(payload.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Request-Id": "request"])!)
        }, currentDate: { Date(timeIntervalSince1970: 1234) }))
    }
    private func body(_ request: URLRequest) throws -> [String: JSONValue] {
        guard case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!) else { throw CancellationError() }
        return body
    }

    @Test("starts generation with standard request fields and metadata")
    func start() async throws {
        let capture = Capture()
        let result = try await model(capture: capture).doStart(options: .init(prompt: "sunset", n: 1, aspectRatio: "16:9", resolution: "1280x720", duration: 5, generateAudio: true, headers: ["X-Request": "custom"]))
        let request = try #require(await capture.last())
        #expect(request.url?.absoluteString == "https://api.example.com/videos/generations")
        #expect(try body(request) == ["model": .string("grok-imagine-video"), "prompt": .string("sunset"), "aspect_ratio": .string("16:9"), "resolution": .string("720p"), "duration": .number(5), "generate_audio": .bool(true)])
        #expect(request.value(forHTTPHeaderField: "X-Request") == "custom")
        #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
        #expect(result.operation == .object(["requestId": .string("req-123")]))
        #expect(result.warnings.isEmpty)
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 1234))
        #expect(result.response.modelId == "grok-imagine-video")
        #expect(result.response.headers?["x-request-id"] == "request")
    }

    @Test("maps supported resolutions and provider override", arguments: [("854x480", "480p"), ("640x480", "480p"), ("1920x1080", "1080p")])
    func resolutions(_ input: String, _ expected: String) async throws {
        let capture = Capture()
        _ = try await model(modelId: .grokImagineVideo15, capture: capture).doStart(options: .init(n: 1, resolution: input))
        #expect(try body(#require(await capture.last()))["resolution"] == .string(expected))
        _ = try await model(capture: capture).doStart(options: .init(n: 1, resolution: input, providerOptions: ["xai": ["resolution": .string("720p")]]))
        #expect(try body(#require(await capture.last()))["resolution"] == .string("720p"))
    }

    @Test("generation warnings preserve unsupported feature verdicts")
    func warnings() async throws {
        let result = try await model().doStart(options: .init(n: 2, resolution: "bad", fps: 24, seed: 1))
        let features = result.warnings.compactMap { warning -> String? in if case .unsupported(let feature, _) = warning { feature } else { nil } }
        #expect(Set(features) == Set(["n", "resolution", "fps", "seed"]))
    }

    @Test("converts binary, base64, and URL frame images")
    func images() async throws {
        let capture = Capture()
        let frames: [VideoModelV4FrameImage] = [
            .init(image: .file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil), frameType: .firstFrame),
            .init(image: .url(url: "https://example.com/last.png", providerOptions: nil), frameType: .lastFrame)
        ]
        _ = try await model(modelId: .grokImagineVideo15, capture: capture).doStart(options: .init(n: 1, image: .url(url: "https://example.com/ignored.png", providerOptions: nil), frameImages: frames))
        let request = try body(#require(await capture.last()))
        #expect(request["image"] == .object(["url": .string("data:image/png;base64,AQID")]))
        #expect(request["last_frame"] == .object(["url": .string("https://example.com/last.png")]))
        _ = try await model(capture: capture).doStart(options: .init(n: 1, image: .file(mediaType: "image/png", data: .base64("AQID"), providerOptions: nil)))
        #expect(try body(#require(await capture.last()))["image"] == .object(["url": .string("data:image/png;base64,AQID")]))
    }

    @Test("edit and extension route endpoints and warn about unsupported settings", arguments: ["edit-video", "extend-video"])
    func modes(_ mode: String) async throws {
        let capture = Capture()
        let result = try await model(capture: capture).doStart(options: .init(prompt: "edit", n: 1, aspectRatio: "16:9", resolution: "1280x720", duration: 5, generateAudio: true, providerOptions: ["xai": ["mode": .string(mode), "videoUrl": .string("https://example.com/source.mp4"), "user": .string("user"), "custom": .number(7)]]))
        let request = try #require(await capture.last())
        #expect(request.url?.path == (mode == "edit-video" ? "/videos/edits" : "/videos/extensions"))
        let data = try body(request)
        #expect(data["video"] == .object(["url": .string("https://example.com/source.mp4")]))
        #expect(data["custom"] == .number(7))
        #expect(data["duration"] == (mode == "edit-video" ? nil : .number(5)))
        #expect(data["aspect_ratio"] == nil)
        #expect(data["resolution"] == nil)
        #expect(data["generate_audio"] == nil)
        #expect(data["user"] == (mode == "edit-video" ? .string("user") : nil))
        let features = result.warnings.compactMap { if case .unsupported(let feature, _) = $0 { feature } else { nil } }
        #expect(Set(features) == Set(mode == "edit-video" ? ["duration", "aspectRatio", "resolution", "generateAudio"] : ["aspectRatio", "resolution", "generateAudio"]))
    }

    @Test("reference generation maps image/audio inputs, voices, storage, and keyframes")
    func references() async throws {
        let capture = Capture()
        let result = try await model(modelId: .grokImagineVideo15, capture: capture).doStart(options: .init(n: 1, resolution: "1920x1080", inputReferences: [
            .url(url: "https://example.com/image.png", providerOptions: nil),
            .file(mediaType: "audio/wav", data: .binary(Data([1])), providerOptions: nil),
            .url(url: "https://example.com/video.mp4", mediaType: "video/mp4", providerOptions: nil)
        ], providerOptions: ["xai": ["referenceVoiceIds": .array([.string("voice")]), "storageOptions": .object(["filename": .string("clip.mp4"), "expiresAfter": .number(3600), "publicUrl": .object(["expiresAfter": .number(7200)])]), "keyframes": .array([.object(["imageUrl": .string("https://example.com/key.png"), "timestampSeconds": .number(1)])])]]))
        let request = try body(#require(await capture.last()))
        #expect(request["resolution"] == .string("720p"))
        #expect(request["reference_images"] == .array([.object(["url": .string("https://example.com/image.png")])]))
        #expect(request["reference_audios"] == .array([.object(["url": .string("data:audio/wav;base64,AQ==")]), .object(["voice_id": .string("voice")])]))
        #expect(request["storage_options"] == .object(["filename": .string("clip.mp4"), "expires_after": .number(3600), "public_url": .object(["expires_after": .number(7200)])]))
        #expect(request["keyframes"] == .array([.object(["image": .object(["url": .string("https://example.com/key.png")]), "timestamp_s": .number(1)])]))
        #expect(result.warnings.count == 2)
    }

    @Test("status returns completion, billing, storage metadata, and combined headers")
    func completed() async throws {
        let payload = #"{"status":"done","video":{"duration":5,"respect_moderation":true,"file_output":{"file_id":"file","filename":"clip.mp4","expires_at":2000,"public_url":"https://example.com/video.mp4","public_url_expires_at":1900},"storage_error":"warning"},"usage":{"cost_in_usd_ticks":8},"progress":100}"#
        let capture = Capture()
        let result = try await model(payload, capture: capture).doStatus(options: .init(operation: .object(["requestId": .string("../id?query#hash")]), headers: ["X-Request": "request"]))
        let request = try #require(await capture.last())
        #expect(request.url?.absoluteString == "https://api.example.com/videos/..%2Fid%3Fquery%23hash")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
        #expect(request.value(forHTTPHeaderField: "X-Request") == "request")
        guard case .completed(let videos, let warnings, let metadata, let response) = result else { Issue.record("Expected completion"); return }
        #expect(videos == [.url(url: "https://example.com/video.mp4", mediaType: "video/mp4")])
        #expect(warnings.isEmpty)
        #expect(metadata?["xai"]?["costInUsdTicks"] == .number(8))
        #expect(metadata?["xai"]?["duration"] == .number(5))
        #expect(metadata?["xai"]?["progress"] == .number(100))
        #expect(metadata?["xai"]?["storageError"] == .string("warning"))
        #expect(response.timestamp == Date(timeIntervalSince1970: 1234))
        #expect(response.headers?["x-request-id"] == "request")
    }

    @Test("URL-only status responses complete")
    func completedWithoutStatus() async throws {
        let result = try await model(#"{"video":{"url":"https://example.com/video.mp4"}}"#).doStatus(options: .init(operation: .object(["requestId": .string("request")])))
        guard case .completed(let videos, _, _, _) = result else { Issue.record("Expected completion"); return }
        #expect(videos == [.url(url: "https://example.com/video.mp4", mediaType: "video/mp4")])
    }

    @Test("202 bodies produce pending without requiring JSON", arguments: ["", "not json", #"{"status":"pending","progress":0.5}"#])
    func pending(_ payload: String) async throws {
        let result = try await model(payload, status: 202).doStatus(options: .init(operation: .object(["requestId": .string("request")])))
        guard case .pending = result else { Issue.record("Expected pending"); return }
    }

    @Test("terminal status errors are returned as typed verdicts", arguments: [
        (#"{"status":"expired"}"#, "Video generation request expired."),
        (#"{"status":"failed","error":{"message":"bad video"}}"#, "Video generation failed: bad video"),
        (#"{"status":"done","video":{"respect_moderation":false}}"#, "Video generation was blocked due to a content policy violation."),
        (#"{"status":"done"}"#, "Video generation completed but no video URL was returned.")
    ])
    func failed(_ payload: String, _ expected: String) async throws {
        let result = try await model(payload).doStatus(options: .init(operation: .object(["requestId": .string("request")])))
        guard case .error(let error, _, _) = result else { Issue.record("Expected terminal error"); return }
        #expect(error == expected)
    }

    @Test("missing operation identifiers reject generation")
    func missingRequestID() async throws {
        await #expect(throws: (any Error).self) { _ = try await model("{}").doStart(options: .init(n: 1)) }
    }
}
