import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import ReplicateProvider

@Suite("Replicate video operations")
struct ReplicateVideoModelTests {
    private actor Requests {
        var values: [URLRequest] = []
        func record(_ value: URLRequest) { values.append(value) }
        func all() -> [URLRequest] { values }
    }

    @Test("start registers webhook and maps versioned image-to-video input")
    func start() async throws {
        let requests = Requests()
        let fetch: FetchFunction = { request in
            await requests.record(request)
            return response(request, #"{"id":"prediction","status":"starting","urls":{"get":"https://api.replicate.com/v1/predictions/prediction"}}"#)
        }
        let model = createReplicate(settings: .init(apiToken: "token", fetch: fetch)).video("minimax/video-01:version")
        let result = try await model.doStart(options: .init(
            prompt: "A rocket", n: 1, aspectRatio: "16:9", resolution: "1920x1080", duration: 5, fps: 24, seed: 42,
            image: .file(mediaType: "image/png", data: .binary(Data([1, 2])), providerOptions: nil),
            providerOptions: ["replicate": ["guidance_scale": .number(7), "custom": .bool(true), "maxWaitTimeInSeconds": .number(30)]],
            headers: ["X-Request": "value"]
        ), webhookUrl: "https://example.com/webhook")
        #expect(result.operation == .object(["getUrl": .string("https://api.replicate.com/v1/predictions/prediction")]))
        let request = try #require(await requests.all().first)
        #expect(request.url?.absoluteString == "https://api.replicate.com/v1/predictions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body == .object([
            "version": .string("version"), "webhook": .string("https://example.com/webhook"), "webhook_events_filter": .array([.string("completed")]),
            "input": .object(["prompt": .string("A rocket"), "aspect_ratio": .string("16:9"), "size": .string("1920x1080"), "duration": .number(5), "fps": .number(24), "seed": .number(42), "image": .string("data:image/png;base64,AQI="), "guidance_scale": .number(7), "custom": .bool(true)])
        ]))
    }

    @Test("status maps pending, completed, failed and canceled predictions", arguments: ["processing", "succeeded", "failed", "canceled"])
    func status(_ status: String) async throws {
        let fetch: FetchFunction = { request in
            response(request, #"{"id":"prediction","status":"\#(status)","output":"https://cdn.example.com/video.mp4","error":"Insufficient credits","metrics":{"predict_time":2.5},"urls":{"get":"https://api.replicate.com/v1/predictions/prediction"}}"#)
        }
        let model = createReplicate(settings: .init(apiToken: "token", fetch: fetch)).video("minimax/video-01")
        let result = try await model.doStatus(options: .init(operation: .object(["getUrl": .string("https://api.replicate.com/v1/predictions/prediction")])))
        switch (status, result) {
        case ("processing", .pending): break
        case ("succeeded", .completed(let videos, let warnings, let metadata, let info)):
            #expect(videos == [.url(url: "https://cdn.example.com/video.mp4", mediaType: "video/mp4")])
            #expect(warnings.isEmpty)
            #expect(metadata?["replicate"]?["predictionId"] == .string("prediction"))
            #expect(metadata?["replicate"]?["metrics"] == .object(["predict_time": .number(2.5)]))
            #expect(info.modelId == "minimax/video-01")
        case ("failed", .error(let message, _, _)): #expect(message == "Video generation failed: Insufficient credits")
        case ("canceled", .error(let message, _, _)): #expect(message == "Video generation was canceled")
        default: Issue.record("Unexpected status: \(status)")
        }
    }

    @Test("status never forwards credentials to a foreign operation host")
    func foreignStatus() async throws {
        let requests = Requests()
        let fetch: FetchFunction = { request in
            await requests.record(request)
            return response(request, #"{"id":"prediction","status":"processing","urls":{"get":"https://cdn.example.com/prediction"}}"#)
        }
        let model = createReplicate(settings: .init(apiToken: "secret", headers: ["X-Secret": "secret"], fetch: fetch)).video("minimax/video-01")
        _ = try await model.doStatus(options: .init(operation: .object(["getUrl": .string("https://cdn.example.com/prediction")]), headers: ["X-Request": "secret"]))
        let request = try #require(await requests.all().first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Secret") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Request") == nil)
    }

    @Test("completed prediction without output is a typed failure")
    func missingOutput() async throws {
        let fetch: FetchFunction = { request in response(request, #"{"id":"prediction","status":"succeeded","urls":{"get":"https://api.replicate.com/v1/predictions/prediction"}}"#) }
        let model = createReplicate(settings: .init(apiToken: "token", fetch: fetch)).video("minimax/video-01")
        do {
            _ = try await model.doStatus(options: .init(operation: .object(["getUrl": .string("https://api.replicate.com/v1/predictions/prediction")])))
            Issue.record("Expected missing-output error")
        } catch let error as any AISDKError {
            #expect(error.name == "REPLICATE_VIDEO_GENERATION_ERROR")
        }
    }
}

private func response(_ request: URLRequest, _ json: String) -> FetchResponse {
    FetchResponse(body: .data(Data(json.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
}
