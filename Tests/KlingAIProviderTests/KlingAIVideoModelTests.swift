import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import KlingAIProvider

@Suite("KlingAI native V4 video operations")
struct KlingAIVideoModelTests {
    @Test("start maps T2V, I2V, reference images and motion-control", arguments: ["t2v", "i2v", "references", "motion-control"])
    func start(_ mode: String) async throws {
        let endpoint = ["t2v": "text2video", "i2v": "image2video", "references": "multi-image2video", "motion-control": "motion-control"][mode]!
        let id = "kling-v3.0-\(mode == "references" ? "i2v" : mode)"
        let fetch: FetchFunction = { request in
            #expect(request.url?.absoluteString == "https://api-singapore.klingai.com/v1/videos/\(endpoint)")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Request") == "value")
            let json = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            var body: [String: JSONValue] = ["model_name": .string("kling-v3"), "prompt": .string("Animate"), "mode": .string("pro"), "watermark_info": .object(["enabled": .bool(true)]), "custom": .string("value"), "callback_url": .string("https://example.com/webhook")]
            if mode == "motion-control" {
                body["video_url"] = .string("https://example.com/reference.mp4")
                body["character_orientation"] = .string("image")
                body["image_url"] = .string("AQ==")
                body["keep_original_sound"] = .string("no")
                body["element_list"] = .array([.object(["element_id": .number(1)])])
            } else {
                body["negative_prompt"] = .string("Blur")
                body["cfg_scale"] = .number(0.5)
                body["duration"] = .string("5")
                if mode == "references" {
                    body["aspect_ratio"] = .string("16:9")
                    body["image_list"] = .array([.object(["image": .string("https://example.com/reference.png")])])
                } else {
                    body["sound"] = .string("on")
                    body["camera_control"] = .object(["type": .string("simple"), "config": .object(["zoom": .number(1)])])
                    body["multi_shot"] = .bool(true)
                    body["shot_type"] = .string("customize")
                    body["multi_prompt"] = .array([.object(["index": .number(1), "prompt": .string("Shot"), "duration": .string("5")])])
                    body["voice_list"] = .array([.object(["voice_id": .string("voice")])])
                    if mode == "t2v" { body["aspect_ratio"] = .string("16:9") }
                    else {
                        body["image"] = .string("AQ==")
                        body["image_tail"] = .string("https://example.com/last.png")
                        body["static_mask"] = .string("mask")
                        body["dynamic_masks"] = .array([.object(["mask": .string("mask"), "trajectories": .array([.object(["x": .number(1), "y": .number(2)])])])])
                        body["element_list"] = .array([.object(["element_id": .number(1)])])
                    }
                }
            }
            #expect(json == .object(body))
            return klingResponse(request, #"{"code":0,"message":"success","data":{"task_id":"task"}}"#)
        }
        let model = createKlingAI(settings: .init(apiKey: " key ", fetch: fetch)).video(modelId: .init(rawValue: id))
        let providerOptions: [String: JSONValue] = [
            "mode": .string("pro"), "sound": .string("off"), "negativePrompt": .string("Blur"), "cfgScale": .number(0.5),
            "cameraControl": .object(["type": .string("simple"), "config": .object(["zoom": .number(1), "unknown": .bool(true)])]),
            "multiShot": .bool(true), "shotType": .string("customize"), "multiPrompt": .array([.object(["index": .number(1), "prompt": .string("Shot"), "duration": .string("5")])]),
            "elementList": .array([.object(["element_id": .number(1)])]), "voiceList": .array([.object(["voice_id": .string("voice")])]),
            "staticMask": .string("mask"), "dynamicMasks": .array([.object(["mask": .string("mask"), "trajectories": .array([.object(["x": .number(1), "y": .number(2)])])])]),
            "videoUrl": .string("https://example.com/reference.mp4"), "characterOrientation": .string("image"), "keepOriginalSound": .string("no"), "watermarkEnabled": .bool(true),
            "pollIntervalMs": .number(1), "pollTimeoutMs": .number(1), "custom": .string("value")
        ]
        let image = VideoModelV4File.file(mediaType: "image/png", data: .binary(Data([1])), providerOptions: nil)
        let result = try await model.doStart(options: .init(prompt: "Animate", n: 1, aspectRatio: "16:9", duration: 5,
            image: mode == "i2v" || mode == "motion-control" ? image : nil,
            frameImages: mode == "i2v" ? [.init(image: .url(url: "https://example.com/last.png", providerOptions: nil), frameType: .lastFrame)] : nil,
            inputReferences: mode == "references" ? [.url(url: "https://example.com/reference.png", providerOptions: nil)] : nil,
            generateAudio: true, providerOptions: ["klingai": providerOptions], headers: ["X-Request": "value"]
        ), webhookUrl: "https://example.com/webhook")
        #expect(result.operation == .object(["taskId": .string("task"), "endpointPath": .string("/v1/videos/\(endpoint)")]))
    }

    @Test("status reports pending, terminal error and completed metadata", arguments: ["processing", "failed", "succeed"])
    func status(_ status: String) async throws {
        let fetch: FetchFunction = { request in
            #expect(request.url?.path == "/v1/videos/image2video/task")
            return klingResponse(request, #"{"code":0,"message":"success","data":{"task_id":"task","task_status":"\#(status)","task_status_msg":"Refused","task_result":{"videos":[{"id":"video","url":"https://cdn.example.com/video.mp4","watermark_url":"https://cdn.example.com/watermark.mp4","duration":"5"}]}}}"#)
        }
        let model = createKlingAI(settings: .init(apiKey: "key", fetch: fetch)).video(.klingV30I2v)
        let result = try await model.doStatus(options: .init(operation: .object(["taskId": .string("task"), "endpointPath": .string("/v1/videos/image2video")])))
        switch (status, result) {
        case ("processing", .pending): break
        case ("failed", .error(let error, _, _)): #expect(error == "Video generation failed: Refused")
        case ("succeed", .completed(let videos, _, let metadata, let response)):
            #expect(videos == [.url(url: "https://cdn.example.com/video.mp4", mediaType: "video/mp4")])
            #expect(metadata?["klingai"]?["videos"] == .array([.object(["id": .string("video"), "url": .string("https://cdn.example.com/video.mp4"), "watermarkUrl": .string("https://cdn.example.com/watermark.mp4"), "duration": .string("5")])]))
            #expect(response.modelId == "kling-v3.0-i2v")
        default: Issue.record("Unexpected task status")
        }
    }

    @Test("unsupported settings are surfaced without warnings for supported defaults", arguments: [false, true])
    func unsupportedSettings(_ configured: Bool) async throws {
        let fetch: FetchFunction = { request in
            klingResponse(request, #"{"code":0,"message":"success","data":{"task_id":"task"}}"#)
        }
        let model = createKlingAI(settings: .init(apiKey: "key", fetch: fetch)).video(.klingV30T2v)
        let result = try await model.doStart(options: .init(n: configured ? 2 : 1, resolution: configured ? "1920x1080" : "", fps: configured ? 24 : 0, seed: configured ? 42 : 0))
        let features = result.warnings.compactMap { warning -> String? in
            if case .unsupported(let feature, _) = warning { return feature }
            return nil
        }
        #expect(features == (configured ? ["resolution", "seed", "fps", "n"] : []))
        #expect(result.warnings.count == features.count)
    }

    @Test("video references and video frames are rejected as guidance")
    func videoGuidance() async throws {
        let fetch: FetchFunction = { request in
            let json = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(json == .object(["model_name": .string("kling-v3")]))
            return klingResponse(request, #"{"code":0,"message":"success","data":{"task_id":"task"}}"#)
        }
        let model = createKlingAI(settings: .init(apiKey: "key", fetch: fetch)).video(.klingV30I2v)
        let video = VideoModelV4File.url(url: "https://example.com/video.mp4", mediaType: "video/mp4", providerOptions: nil)
        let result = try await model.doStart(options: .init(n: 1, image: video, inputReferences: [video]))
        #expect(result.warnings.count == 2)
    }

    @Test("unknown models, missing motion controls and invalid nested options fail before networking")
    func invalidRequests() async throws {
        let provider = createKlingAI(settings: .init(apiKey: "key"))
        await #expect(throws: NoSuchModelError.self) { try await provider.video("unknown").doStart(options: .init(n: 1)) }
        do { _ = try await provider.video(.klingV26MotionControl).doStart(options: .init(n: 1)); Issue.record("Expected missing motion options") }
        catch let error as any AISDKError { #expect(error.name == "KLINGAI_VIDEO_MISSING_OPTIONS") }
        await #expect(throws: InvalidArgumentError.self) {
            try await provider.video(.klingV30T2v).doStart(options: .init(n: 1, providerOptions: ["klingai": ["cameraControl": .object(["config": .object(["zoom": .number(1)])])]]))
        }
    }

    @Test("missing task IDs, missing video URLs and API errors are surfaced", arguments: ["create", "videos", "http"])
    func failures(_ mode: String) async throws {
        let fetch: FetchFunction = { request in
            if mode == "http" { return klingResponse(request, #"{"code":1001,"message":"Bad request"}"#, status: 400) }
            return klingResponse(request, mode == "create" ? #"{"code":0,"message":"success"}"# : #"{"code":0,"message":"success","data":{"task_id":"task","task_status":"succeed","task_result":{"videos":[]}}}"#)
        }
        let model = createKlingAI(settings: .init(apiKey: "key", fetch: fetch)).video(.klingV30T2v)
        do {
            if mode == "videos" { _ = try await model.doStatus(options: .init(operation: .object(["taskId": .string("task"), "endpointPath": .string("/v1/videos/text2video")]))) }
            else { _ = try await model.doStart(options: .init(n: 1)) }
            Issue.record("Expected API failure")
        } catch let error as any AISDKError {
            #expect(error.name == (mode == "http" ? "AI_APICallError" : "KLINGAI_VIDEO_GENERATION_ERROR"))
        }
    }
}

private func klingResponse(_ request: URLRequest, _ json: String, status: Int = 200) -> FetchResponse {
    FetchResponse(body: .data(Data(json.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
}
