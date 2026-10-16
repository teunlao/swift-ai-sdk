import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalVideoModel")
struct FalVideoModelTests {
    private let queueURL = "https://queue.fal.run/fal-ai/luma-dream-machine"
    private let statusURL = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/job"
    private let date = Date(timeIntervalSince1970: 1_704_067_200)

    private actor Capture {
        var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
        func all() -> [URLRequest] { requests }
    }

    private func response(_ request: URLRequest, status: Int = 200, body: String) -> FetchResponse {
        .init(
            body: .data(Data(body.utf8)),
            urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Type": "application/json", "x-request-id": "response-id"])!
        )
    }

    private func makeModel(modelId: FalVideoModelId = "luma-dream-machine", fetch: @escaping FetchFunction) -> FalVideoModel {
        FalVideoModel(modelId: modelId, config: .init(
            provider: "fal.video", url: { $0.path }, headers: { ["Authorization": "Key secret"] },
            fetch: fetch, currentDate: { date }
        ))
    }

    private var operation: JSONValue {
        .object(["responseUrl": .string(statusURL), "submitUrl": .string(queueURL)])
    }

    @Test("start serializes generation options, provider overrides and webhook without polling")
    func startsOperation() async throws {
        let capture = Capture()
        let model = makeModel(modelId: "fal-ai/luma-dream-machine") { request in
            await capture.record(request)
            return response(request, body: #"{"request_id":"job","response_url":"\#(statusURL)"}"#)
        }
        let webhook = "https://example.com/hook?token=a b&n=1"
        let result = try await model.doStart(options: .init(
            prompt: "city", n: 1, aspectRatio: "16:9", duration: 5, seed: 42,
            image: .file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil),
            providerOptions: ["fal": [
                "loop": .bool(false), "motionStrength": .number(0.5), "resolution": .string("1080p"),
                "negativePrompt": .string("blur"), "promptOptimizer": .bool(true), "custom": .null,
                "duration": .string("10s"), "pollIntervalMs": .number(0),
            ]], headers: ["x-client": "client"]
        ), webhookUrl: webhook)
        let requests = await capture.all()
        let request = try #require(requests.first)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [.init(name: "fal_webhook", value: webhook)])
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Key secret")
        #expect(request.value(forHTTPHeaderField: "x-client") == "client")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body == .object([
            "prompt": .string("city"), "aspect_ratio": .string("16:9"), "duration": .string("10s"),
            "seed": .number(42), "image_url": .string("data:image/png;base64,AQID"),
            "loop": .bool(false), "motion_strength": .number(0.5), "resolution": .string("1080p"),
            "negative_prompt": .string("blur"), "prompt_optimizer": .bool(true), "custom": .null,
            "pollIntervalMs": .number(0),
        ]))
        #expect(result.operation == .object([
            "responseUrl": .string(statusURL), "submitUrl": .string(request.url!.absoluteString),
        ]))
        #expect(result.response.timestamp == date)
        #expect(result.response.headers == nil)
    }

    @Test("start handles URL and base64 images and omits zero-valued generation settings", arguments: [false, true])
    func inputImages(base64: Bool) async throws {
        let capture = Capture()
        let model = makeModel(modelId: "fal/luma-dream-machine") { request in
            await capture.record(request)
            return response(request, body: #"{"response_url":"\#(statusURL)"}"#)
        }
        let image: VideoModelV4File = base64
            ? .file(mediaType: "image/png", data: .base64("AQID"), providerOptions: nil)
            : .url(url: "https://example.com/input.png", providerOptions: nil)
        _ = try await model.doStart(options: .init(
            prompt: "", n: 1, duration: 0, seed: 0, image: image,
            providerOptions: ["fal": ["loop": .null, "motionStrength": .null]]
        ))
        let request = try #require(await capture.all().first)
        #expect(request.url?.absoluteString == queueURL)
        #expect(try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody)) == .object([
            "prompt": .string(""),
            "image_url": .string(base64 ? "data:image/png;base64,AQID" : "https://example.com/input.png"),
        ]))
    }

    @Test("status returns pending without orchestrating polling")
    func pendingStatus() async throws {
        let model = makeModel { request in
            response(request, status: 400, body: #"{"detail":"Request is still in progress"}"#)
        }
        let result = try await model.doStatus(options: .init(operation: operation))
        guard case .pending(let warnings, _, let info) = result else {
            Issue.record("Expected pending operation")
            return
        }
        #expect(warnings == nil)
        #expect(info.timestamp == date)
        #expect(info.modelId == "luma-dream-machine")
        #expect(info.headers == nil)
    }

    @Test("completed status returns video URL and parsed metadata while retaining nullable fields")
    func completedStatus() async throws {
        let model = makeModel { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Key secret")
            return response(request, body: #"{"video":{"url":"https://fal.media/video.mp4","width":1920,"height":1080,"duration":5,"fps":24,"content_type":"video/webm","unknown":true},"seed":null,"timings":{"inference":null,"extra":1},"has_nsfw_concepts":null,"prompt":"revised"}"#)
        }
        let result = try await model.doStatus(options: .init(operation: operation))
        guard case .completed(let videos, let warnings, let metadata, let info) = result else {
            Issue.record("Expected completed operation")
            return
        }
        #expect(videos == [.url(url: "https://fal.media/video.mp4", mediaType: "video/webm")])
        #expect(warnings.isEmpty)
        #expect(metadata?["fal"] == [
            "videos": .array([.object([
                "url": .string("https://fal.media/video.mp4"), "width": .number(1920), "height": .number(1080),
                "duration": .number(5), "fps": .number(24), "contentType": .string("video/webm"),
            ])]), "seed": .null, "timings": .object(["inference": .null]), "has_nsfw_concepts": .null,
            "prompt": .string("revised"),
        ])
        #expect(info.headers?["x-request-id"] == "response-id")
    }

    @Test("missing or empty media type defaults to video/mp4", arguments: [#"{}"#, #"{"content_type":null}"#, #"{"content_type":""}"#])
    func defaultMediaType(fields: String) async throws {
        let suffix = String(fields.dropFirst().dropLast())
        let model = makeModel { request in
            response(request, body: "{\"video\":{\"url\":\"https://fal.media/video.mp4\"\(suffix.isEmpty ? "" : "," + suffix)}}")
        }
        guard case .completed(let videos, _, _, _) = try await model.doStatus(options: .init(operation: operation)) else {
            Issue.record("Expected completed operation")
            return
        }
        #expect(videos == [.url(url: "https://fal.media/video.mp4", mediaType: "video/mp4")])
    }

    @Test("API and malformed success responses become error statuses", arguments: [false, true])
    func errorStatus(malformed: Bool) async throws {
        let model = makeModel { request in
            response(request, status: malformed ? 200 : 422,
                     body: malformed ? #"{"video":{"url":3}}"# : #"{"error":{"message":"invalid generation","code":422}}"#)
        }
        guard case .error(let message, _, let info) = try await model.doStatus(options: .init(operation: operation)) else {
            Issue.record("Expected error status")
            return
        }
        #expect(message == (malformed ? "Invalid JSON response" : "invalid generation"))
        #expect(info.headers?["x-request-id"] == "response-id")
    }

    @Test("queue rejection remains a thrown API error")
    func queueError() async throws {
        let model = makeModel { request in
            response(request, status: 403, body: #"{"error":{"message":"denied","code":403}}"#)
        }
        do {
            _ = try await model.doStart(options: .init(n: 1))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "denied")
            #expect(error.statusCode == 403)
        }
    }

    @Test("missing queue response URL and completed video remain generation errors", arguments: [false, true])
    func missingURLs(status: Bool) async throws {
        let model = makeModel { request in response(request, body: "{}") }
        do {
            if status { _ = try await model.doStatus(options: .init(operation: operation)) }
            else { _ = try await model.doStart(options: .init(n: 1)) }
            Issue.record("Expected generation error")
        } catch let error as any AISDKError {
            #expect(error.name == "FAL_VIDEO_GENERATION_ERROR")
            #expect(error.message == (status ? "No video URL in response" : "No response URL returned from queue endpoint"))
        }
    }

    @Test("invalid model options fail before queue submission")
    func invalidOptions() async throws {
        let model = makeModel { _ in throw CancellationError() }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doStart(options: .init(n: 1, providerOptions: ["fal": ["motionStrength": .number(2)]]))
        }
    }

    @Test("status URL from queue cannot receive credentials on a foreign origin")
    func foreignStatusCredentials() async throws {
        let model = makeModel { request in
            #expect(request.url?.host == "cdn.example.net")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "x-private") == nil)
            return response(request, body: #"{"video":{"url":"https://fal.media/video.mp4"}}"#)
        }
        let result = try await model.doStatus(options: .init(
            operation: .object(["submitUrl": .string(queueURL), "responseUrl": .string("https://cdn.example.net/status")]),
            headers: ["x-private": "secret"]
        ))
        guard case .completed(let videos, _, _, _) = result else {
            Issue.record("Expected completed operation")
            return
        }
        #expect(videos.count == 1)
    }

    @Test("status rejects private response URLs before sending credentials")
    func privateStatusURL() async throws {
        let model = makeModel { _ in throw CancellationError() }
        await #expect(throws: DownloadError.self) {
            _ = try await model.doStatus(options: .init(operation: .object([
                "submitUrl": .string(queueURL), "responseUrl": .string("http://127.0.0.1/status"),
            ])))
        }
    }

    @Test("webhook registration preserves the received notification")
    func webhookRegistration() async throws {
        let model = makeModel { _ in throw CancellationError() }
        let notification = VideoModelV4OperationWebhook(headers: ["x-signature": "signed"], body: .object(["request_id": .string("job")]))
        let registration = try await model.handleWebhookOption {
            .init(url: "https://example.com/webhook", received: Task { notification })
        }
        #expect(registration.webhookUrl == "https://example.com/webhook")
        #expect(try await registration.received.value == notification)
    }

    @Test("abort remains cancellation rather than an error status")
    func cancellation() async throws {
        let model = makeModel { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) {
            _ = try await model.doStatus(options: .init(operation: operation, abortSignal: { true }))
        }
    }
}
