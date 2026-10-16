import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import BlackForestLabsProvider

@Suite("Black Forest Labs native V4 API contracts")
struct BlackForestLabsV4Tests {
    @Test("image APIs map editing inputs to the endpoint's native shape", arguments: ["flux-pro-1.0-fill", "flux-3-image", "flux-3-image-klein"])
    func imageAPIs(_ id: String) async throws {
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST" {
                let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
                if id == "flux-pro-1.0-fill" {
                    #expect(body == .object(["prompt": .string("Edit"), "image": .string("AQ=="), "mask": .string("https://example.com/mask.png"), "aspect_ratio": .string("1:1"), "seed": .number(12)]))
                } else if id == "flux-3-image" {
                    #expect(body == .object(["prompt": .string("Edit"), "images": .array([.string("AQ==")]), "aspect_ratio": .string("1:1"), "resolution": .string("2k"), "grounding": .bool(true), "safety_tolerance": .number(7)]))
                } else {
                    #expect(body == .object(["prompt": .string("Edit"), "images": .array([.string("AQ==")]), "width": .number(1024), "height": .number(768), "seed": .number(12), "safety_tolerance": .number(7)]))
                }
                #expect(request.value(forHTTPHeaderField: "x-key") == "secret")
                return bflResponse(request, #"{"id":"generation","polling_url":"https://api.bfl.ai/v1/poll"}"#)
            }
            if request.url!.path.contains("poll") { return bflResponse(request, #"{"status":"Ready","result":{"sample":"https://cdn.example.com/image.png"}}"#) }
            #expect(request.value(forHTTPHeaderField: "x-key") == nil)
            return bflResponse(request, Data([1]))
        }
        let model = createBlackForestLabs(settings: .init(apiKey: "secret", fetch: fetch)).image(.init(rawValue: id))
        let result = try await model.doGenerate(options: .init(
            prompt: "Edit", n: 1, size: id == "flux-3-image-klein" ? "1024x768" : nil, aspectRatio: "1:1", seed: 12,
            files: [.file(mediaType: "image/png", data: .binary(Data([1])), providerOptions: nil)],
            mask: id == "flux-pro-1.0-fill" ? .url(url: "https://example.com/mask.png", providerOptions: nil) : nil,
            providerOptions: id == "flux-pro-1.0-fill" ? [:] : ["blackForestLabs": ["resolution": .string("2k"), "grounding": .bool(true), "safetyTolerance": .number(7)]]
        ))
        #expect(result.images == .binary([Data([1])]))
        if id == "flux-3-image" { #expect(result.warnings == [.unsupported(feature: "seed", details: nil)]) }
    }

    @Test("latest image dimensions and masks are validated at the public boundary")
    func rejectsDimensionsAndMasks() async throws {
        let model = createBlackForestLabs(settings: .init(apiKey: "token")).image(.flux3ImageKlein)
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(n: 1, providerOptions: ["blackForestLabs": ["width": .number(1024)]]))
        }
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(n: 1, size: "6256x6256"))
        }
        await #expect(throws: UnsupportedFunctionalityError.self) {
            try await model.doGenerate(options: .init(n: 1, mask: .url(url: "https://example.com/mask.png", providerOptions: nil)))
        }
    }

    @Test("video start maps text, keyframes, continuation and draft replay", arguments: ["text", "frames", "continuation", "draft"])
    func videoStart(_ mode: String) async throws {
        let fetch: FetchFunction = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            let expected: [String: JSONValue]
            switch mode {
            case "draft": expected = ["mode": .string("draft_enhance"), "draft_cache": .string("bundle"), "safety_tolerance": .number(2)]
            case "frames": expected = ["mode": .string("i2v"), "prompt": .string("Animate"), "resolution": .string("hd"), "duration": .number(5), "generate_audio": .bool(true), "keyframes": .array([.string("AQ=="), .string("https://example.com/last.png")])]
            case "continuation": expected = ["mode": .string("v2v"), "prompt": .string("Animate"), "resolution": .string("hd"), "duration": .number(5), "generate_audio": .bool(true), "start_video": .string("https://example.com/video.mp4")]
            default: expected = ["mode": .string("t2v"), "prompt": .string("Animate"), "resolution": .string("hd"), "duration": .number(5), "generate_audio": .bool(true)]
            }
            #expect(body == .object(expected))
            return bflResponse(request, #"{"id":"generation","polling_url":"https://api.us1.bfl.ai/poll","cost":1,"input_mp":2}"#)
        }
        let model = createBlackForestLabs(settings: .init(apiKey: "token", fetch: fetch)).video(.flux3Video)
        let first = VideoModelV4File.file(mediaType: "image/png", data: .binary(Data([1])), providerOptions: nil)
        let result = try await model.doStart(options: .init(prompt: "Animate", n: 1, resolution: "1280x720", duration: 3,
            image: mode == "frames" ? first : nil,
            frameImages: mode == "frames" ? [.init(image: .url(url: "https://example.com/last.png", providerOptions: nil), frameType: .lastFrame)] : nil,
            inputReferences: mode == "continuation" ? [.url(url: "https://example.com/video.mp4", mediaType: "video/mp4", providerOptions: nil)] : nil,
            generateAudio: true,
            providerOptions: mode == "draft" ? ["blackForestLabs": ["draftCache": .string("bundle"), "safetyTolerance": .number(2)]] : nil
        ))
        #expect(result.operation == .object(["requestId": .string("generation"), "pollingUrl": .string("https://api.us1.bfl.ai/poll"), "cost": .number(1), "inputMegapixels": .number(2)]))
    }

    @Test("video status preserves settled costs and draft-cache metadata")
    func videoCompleted() async throws {
        let fetch: FetchFunction = { request in
            #expect(request.value(forHTTPHeaderField: "x-key") == "secret")
            #expect(request.url?.query == "id=generation")
            return bflResponse(request, #"{"state":"Ready","cost":2,"result":{"sample":"https://cdn.example.com/video.mp4","duration":5,"draft_cache":"https://cdn.example.com/draft.bin"}}"#)
        }
        let model = createBlackForestLabs(settings: .init(apiKey: "secret", fetch: fetch)).video(.flux3Video)
        let result = try await model.doStatus(options: .init(operation: .object(["requestId": .string("generation"), "pollingUrl": .string("https://api.us1.bfl.ai/poll"), "cost": .number(1)])))
        guard case .completed(let videos, _, let metadata, _) = result else { Issue.record("Expected completed video"); return }
        #expect(videos == [.url(url: "https://cdn.example.com/video.mp4", mediaType: "video/mp4")])
        #expect(metadata?["blackForestLabs"]?["videos"] == .array([.object(["id": .string("generation"), "videoUrl": .string("https://cdn.example.com/video.mp4"), "duration": .number(5), "draftCache": .string("https://cdn.example.com/draft.bin"), "cost": .number(2)])]))
    }

    @Test("terminal moderation is an error result and HTTP failures are not retryable")
    func moderation() async throws {
        let fetch: FetchFunction = { request in bflResponse(request, #"{"status":"Content Moderated","details":"Refused"}"#) }
        let model = createBlackForestLabs(settings: .init(apiKey: "secret", fetch: fetch)).video(.flux3Video)
        let result = try await model.doStatus(options: .init(operation: .object(["requestId": .string("generation"), "pollingUrl": .string("https://cdn.example.com/poll")])))
        guard case .error(let message, _, _) = result else { Issue.record("Expected moderation failure"); return }
        #expect(message == "Black Forest Labs video generation failed with status \"Content Moderated\": Refused. Request id: generation")
        let failingFetch: FetchFunction = { request in bflResponse(request, #"{"state":"Failed"}"#, status: 503) }
        let failedModel = createBlackForestLabs(settings: .init(apiKey: "secret", fetch: failingFetch)).video(.flux3Video)
        do {
            _ = try await failedModel.doStart(options: .init(n: 1))
            Issue.record("Expected failed task HTTP response")
        } catch let error as APICallError { #expect(error.isRetryable == false) }
    }

    @Test("untimed keyframe count and timed ordering are enforced before networking")
    func invalidKeyframes() async throws {
        let model = createBlackForestLabs(settings: .init(apiKey: "secret")).video(.flux3Video)
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doStart(options: .init(n: 1, providerOptions: ["blackForestLabs": ["keyframes": .array([.string("a"), .string("b"), .string("c")])]]))
        }
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doStart(options: .init(n: 1, providerOptions: ["blackForestLabs": ["keyframes": .array([.array([.number(3), .string("a")]), .array([.number(1), .string("b")])])]]))
        }
    }
}

private func bflResponse(_ request: URLRequest, _ json: String, status: Int = 200) -> FetchResponse {
    FetchResponse(body: .data(Data(json.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
}
private func bflResponse(_ request: URLRequest, _ data: Data) -> FetchResponse {
    FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!)
}
