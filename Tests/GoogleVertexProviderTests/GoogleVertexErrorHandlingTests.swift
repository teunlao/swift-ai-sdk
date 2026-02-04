import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexProvider error handling")
struct GoogleVertexErrorHandlingTests {
    @Test("Embedding model extracts message from Vertex error payload")
    func embeddingModel_extractsErrorMessage() async throws {
        let errorJSON: [String: Any] = [
            "error": [
                "code": 400,
                "message": "bad request from vertex",
                "status": "INVALID_ARGUMENT"
            ]
        ]
        let errorData = try JSONSerialization.data(withJSONObject: errorJSON)

        let fetch: FetchFunction = { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return FetchResponse(body: .data(errorData), urlResponse: response)
        }

        let model = GoogleVertexEmbeddingModel(
            modelId: GoogleVertexEmbeddingModelId(rawValue: "textembedding-gecko@001"),
            config: GoogleVertexEmbeddingConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { [:] as [String: String?] },
                fetch: fetch
            )
        )

        do {
            _ = try await model.doEmbed(options: .init(values: ["hello"]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.message == "bad request from vertex")
            #expect(error.statusCode == 400)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }

    @Test("Image model extracts message from Vertex error payload")
    func imageModel_extractsErrorMessage() async throws {
        let errorJSON: [String: Any] = [
            "error": [
                "code": 403,
                "message": "permission denied",
                "status": "PERMISSION_DENIED"
            ]
        ]
        let errorData = try JSONSerialization.data(withJSONObject: errorJSON)

        let fetch: FetchFunction = { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 403,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return FetchResponse(body: .data(errorData), urlResponse: response)
        }

        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "imagen-3.0-generate-002"),
            config: GoogleVertexImageModelConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { [:] as [String: String?] },
                fetch: fetch
            )
        )

        do {
            _ = try await model.doGenerate(options: ImageModelV3CallOptions(prompt: "test", n: 1, providerOptions: [:]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.message == "permission denied")
            #expect(error.statusCode == 403)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }
}

