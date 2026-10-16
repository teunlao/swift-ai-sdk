import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex video operations V4")
struct GoogleVertexVideoModelTests {
    @Test func startAndComplete() async throws {
        let requests = VertexRequests()
        let model = vertexProvider { request in
            await requests.append(request)
            if request.url?.absoluteString.hasSuffix(":predictLongRunning") == true {
                return try vertexResponse(request, #"{"name":"operations/video-1"}"#)
            }
            return try vertexResponse(request, #"{"done":true,"response":{"videos":[{"bytesBase64Encoded":"AQID","mimeType":"video/webm"},{"gcsUri":"gs://bucket/video%2F1.mp4"}]}}"#)
        }.video(modelId: .veo31Generate001)
        let start = try await model.doStart(options: .init(
            prompt: "city", n: 2, aspectRatio: "16:9", resolution: "1920x1080", duration: 8, seed: 42,
            image: .file(mediaType: "image/jpeg", data: .base64("ignored"), providerOptions: nil),
            frameImages: [
                .init(image: .url(url: "gs://bucket/first%2F.png", providerOptions: nil), frameType: .firstFrame),
                .init(image: .file(mediaType: "", data: .binary(Data([1, 2, 3])), providerOptions: nil), frameType: .lastFrame)
            ],
            inputReferences: [.url(url: "gs://bucket/unused.png", providerOptions: nil)], generateAudio: false,
            providerOptions: [
                "googleVertex": ["generateAudio": .bool(true), "personGeneration": .string("allow_adult"), "negativePrompt": .string("blur"), "custom": .number(5)],
                "vertex": ["personGeneration": .string("dont_allow")]
            ]
        ))
        #expect(start.operation == .object(["operationName": .string("operations/video-1")]))
        let first = try #require(await requests.last)
        #expect(try vertexBody(first) == .object([
            "instances": .array([.object([
                "prompt": .string("city"),
                "image": .object(["gcsUri": .string("gs://bucket/first%2F.png"), "mimeType": .string("image/png")]),
                "lastFrame": .object(["bytesBase64Encoded": .string("AQID"), "mimeType": .string("image/png")])
            ])]),
            "parameters": .object([
                "sampleCount": .number(2), "aspectRatio": .string("16:9"), "resolution": .string("1080p"),
                "durationSeconds": .number(8), "seed": .number(42), "generateAudio": .bool(false),
                "personGeneration": .string("allow_adult"), "negativePrompt": .string("blur"), "custom": .number(5)
            ])
        ]))
        let status = try await model.doStatus(options: .init(operation: start.operation, headers: ["x-status": "status"]))
        guard case .completed(let videos, _, let metadata, let response) = status else { Issue.record("Expected completed video"); return }
        #expect(videos == [.base64(data: "AQID", mediaType: "video/webm"), .url(url: "gs://bucket/video%2F1.mp4", mediaType: "video/mp4")])
        #expect(metadata?["googleVertex"] == metadata?["vertex"])
        #expect(metadata?["googleVertex"] == metadata?["google-vertex"])
        #expect(metadata?["googleVertex"]?["videos"] == .array([
            .object(["mimeType": .string("video/webm")]), .object(["gcsUri": .string("gs://bucket/video%2F1.mp4")])
        ]))
        #expect(response.headers?["x-request-id"] == "vertex-request")
        let statusRequest = try #require(await requests.last)
        #expect(try vertexBody(statusRequest) == start.operation)
        #expect(statusRequest.value(forHTTPHeaderField: "x-status") == "status")
    }

    @Test func referenceImagesAndUnsupportedURLs() async throws {
        let requests = VertexRequests()
        let model = vertexProvider { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"name":"operations/reference"}"#)
        }.video(modelId: .veo31Generate001)
        let start = try await model.doStart(options: .init(n: 1, inputReferences: [
            .url(url: "https://example.com/ignored.png", providerOptions: nil),
            .url(url: "gs://bucket/reference.png", providerOptions: nil)
        ], providerOptions: ["vertex": ["referenceImages": .array([.object(["gcsUri": .string("gs://fallback")])])]]))
        #expect(start.warnings.contains { if case .unsupported(feature: "URL-based image input", details: _) = $0 { return true }; return false })
        let request = try #require(await requests.last)
        #expect(try vertexBody(request) == .object([
            "instances": .array([.object(["referenceImages": .array([.object([
                "image": .object(["gcsUri": .string("gs://bucket/reference.png"), "mimeType": .string("image/png")]), "referenceType": .string("asset")
            ])])])]), "parameters": .object(["sampleCount": .number(1)])
        ]))
    }

    @Test(arguments: [false, true])
    func pendingAndError(failed: Bool) async throws {
        let model = vertexProvider { request in
            try vertexResponse(request, failed ? #"{"done":true,"error":{"code":400,"message":"Invalid video","status":"INVALID_ARGUMENT"}}"# : #"{"done":false}"#)
        }.video(modelId: .veo31Generate001)
        let status = try await model.doStatus(options: .init(operation: .object(["operationName": .string("operations/pending")])) )
        switch status {
        case .pending: #expect(failed == false)
        case .error(let error, _, _): #expect(failed); #expect(error == "Video generation failed: Invalid video")
        case .completed: Issue.record("Unexpected video")
        }
    }

    @Test func invalidOperationResponses() async throws {
        let missingName = vertexProvider { request in try vertexResponse(request, "{}") }.video(modelId: .veo31Generate001)
        do {
            _ = try await missingName.doStart(options: .init(n: 1))
            Issue.record("Expected missing operation name")
        } catch let error as any AISDKError { #expect(error.name == "VERTEX_VIDEO_GENERATION_ERROR") }
        let missingVideos = vertexProvider { request in try vertexResponse(request, #"{"done":true,"response":{"videos":[{}]}}"#) }.video(modelId: .veo31Generate001)
        do {
            _ = try await missingVideos.doStatus(options: .init(operation: .object(["operationName": .string("operations/invalid")])))
            Issue.record("Expected invalid videos error")
        } catch let error as any AISDKError { #expect(error.name == "VERTEX_VIDEO_GENERATION_ERROR") }
    }
}
