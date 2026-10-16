import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex image V4")
struct GoogleVertexImageModelTests {
    @Test(arguments: ["googleVertex", "vertex"])
    func generatesImagesWithOptions(namespace: String) async throws {
        let requests = VertexRequests()
        let model = try vertexProvider { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"candidates":[{"content":{"parts":[{"text":"ignored"},{"inlineData":{"mimeType":"image/png","data":"AQID"}},{"inlineData":{"mimeType":"audio/wav","data":"BAUG"}}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":20,"totalTokenCount":30}}"#)
        }.imageModel(modelId: "gemini-3.1-flash-image-preview")
        let result = try await model.doGenerate(options: .init(
            prompt: "Sunset", n: 1, size: "1024x1024", aspectRatio: "16:9", seed: 42,
            providerOptions: [namespace: [
                "responseModalities": .array([.string("TEXT")]),
                "imageConfig": .object(["aspectRatio": .string("1:1"), "imageSize": .string("2K")])
            ]]
        ))
        #expect(result.images == .base64(["AQID"]))
        #expect(result.usage?.inputTokens == 10)
        #expect(result.usage?.outputTokens == 20)
        #expect(result.usage?.totalTokens == 30)
        #expect(result.providerMetadata?["googleVertex"]?.images == [.object([:])])
        #expect(result.providerMetadata?["vertex"]?.images == [.object([:])])
        #expect(result.response.headers?["x-request-id"] == "vertex-request")
        #expect(result.warnings.contains { if case .unsupported(feature: "size", details: _) = $0 { return true }; return false })
        let request = try #require(await requests.last)
        guard case .object(let body) = try vertexBody(request), case .object(let config) = body["generationConfig"] else {
            Issue.record("Missing generation config"); return
        }
        #expect(config["responseModalities"] == .array([.string("IMAGE")]))
        #expect(config["imageConfig"] == .object(["aspectRatio": .string("16:9"), "imageSize": .string("2K")]))
        #expect(config["seed"] == .number(42))
    }

    @Test func contentFilterIsNotRetryable() async throws {
        let model = try vertexProvider { request in
            try vertexResponse(request, #"{"candidates":[{"finishReason":"IMAGE_SAFETY"}]}"#)
        }.imageModel(modelId: "gemini-2.5-flash-image")
        let result = try await model.doGenerate(options: .init(prompt: "image", n: 1))
        #expect(result.images == .base64([]))
        #expect(result.isRetryable == false)
    }

    @Test func rejectsUnsupportedImageModel() async throws {
        let model = try vertexProvider { _ in throw CancellationError() }.imageModel(modelId: "imagen-4.0-generate-001")
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(options: .init(prompt: "image", n: 1))
        }
    }
}
