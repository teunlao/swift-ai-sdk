import Testing
import AISDKProvider
import GoogleVertexProvider

@Suite("Vertex HTTP failures")
struct GoogleVertexErrorHandlingTests {
    @Test func preservesStructuredAPIError() async throws {
        let model = try vertexProvider { request in
            try vertexResponse(request, #"{"error":{"code":400,"message":"Bad embedding dimensions","status":"INVALID_ARGUMENT"}}"#, status: 400)
        }.embeddingModel(modelId: "text-embedding-005")
        do {
            _ = try await model.doEmbed(options: .init(values: ["value"]))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "Bad embedding dimensions")
            #expect(error.statusCode == 400)
            #expect(error.url == "https://vertex.example/models/text-embedding-005:predict")
            #expect(error.responseHeaders?["x-request-id"] == "vertex-request")
        }
    }

    @Test func rejectsMalformedSuccessfulResponse() async throws {
        let model = try vertexProvider { request in try vertexResponse(request, #"{"predictions":[{"embeddings":{"values":"invalid"}}]}"#) }.embeddingModel(modelId: "text-embedding-005")
        await #expect(throws: APICallError.self) { _ = try await model.doEmbed(options: .init(values: ["value"])) }
    }
}
