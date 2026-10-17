import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google video V4 operations")
struct GoogleVideoModelTests {
    @Test("start maps frame inputs and status preserves credential-free media URLs")
    func videoOperations() async throws {
        let transport = GoogleTransport([.init(try googleFixture("video-start.json")), .init(try googleFixture("video-start.json")), .init(try googleFixture("video-done.json"))])
        let model = await transport.provider().video(modelId: "veo-3.1-generate")
        let start = try await model.doStart(options: .init(prompt: "ocean", n: 2, resolution: "3840x2160", duration: 8, frameImages: [.init(image: .file(mediaType: "image/jpeg", data: .binary(Data([1, 2])), providerOptions: nil), frameType: .firstFrame), .init(image: .url(url: "gs://bucket/last.png", providerOptions: nil), frameType: .lastFrame)], providerOptions: ["google": ["generateAudio": .bool(true)]]))
        #expect(start.operation == .object(["operationName": .string("operations/video-op")]))
        let pending = try await model.doStatus(options: .init(operation: start.operation))
        guard case .pending = pending else { Issue.record("expected pending operation"); return }
        let completed = try await model.doStatus(options: .init(operation: start.operation))
        guard case .completed(let videos, _, let metadata, _) = completed else { Issue.record("expected completed operation"); return }
        #expect(videos == [.url(url: "https://provider.example/download/video.mp4?alt=media", mediaType: "video/mp4"), .url(url: "https://other.example/video.mp4", mediaType: "video/mp4")])
        #expect(array(metadata?["google"]?["videos"]).count == 2)
        let requests = await transport.captured()
        let body = try googleBody(requests[0])
        let instance = object(array(body["instances"]).first)
        #expect(object(instance["image"])["bytesBase64Encoded"] == .string("AQI="))
        #expect(object(instance["lastFrame"])["gcsUri"] == .string("gs://bucket/last.png"))
        #expect(object(body["parameters"])["resolution"] == .string("4k"))
        #expect(object(body["parameters"])["generateAudio"] == .bool(true))
        #expect(requests[1].url?.path == "/v1beta/operations/video-op")
    }

    @Test("status reports provider failure without polling or a transport retry")
    func videoFailure() async throws {
        let failure: JSONValue = .object(["done": .bool(true), "error": .object(["code": .number(400), "message": .string("invalid duration")])])
        let transport = GoogleTransport([.init(try googleData(failure))])
        let model = await transport.provider().video(modelId: "veo-3.1-generate")
        let result = try await model.doStatus(options: .init(operation: .object(["operationName": .string("operations/failure")])))
        guard case .error(let error, _, _) = result else { Issue.record("expected failed operation"); return }
        #expect(error == "Video generation failed: invalid duration")
    }
}
