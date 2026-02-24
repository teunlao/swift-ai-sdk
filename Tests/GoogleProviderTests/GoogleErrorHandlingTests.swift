import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleProvider

@Suite("GoogleProvider error handling")
struct GoogleErrorHandlingTests {
    @Test("Embedding model extracts message from Google error payload")
    func embeddingModel_extractsErrorMessage() async throws {
        let errorJSON: [String: Any] = [
            "error": [
                "code": 400,
                "message": "bad request from google",
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

        let model = GoogleGenerativeAIEmbeddingModel(
            modelId: GoogleGenerativeAIEmbeddingModelId(rawValue: "text-embedding-004"),
            config: GoogleGenerativeAIEmbeddingConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com",
                headers: { [:] as [String: String?] },
                fetch: fetch
            )
        )

        do {
            _ = try await model.doEmbed(options: .init(values: ["hello"]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.message == "bad request from google")
            #expect(error.statusCode == 400)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }

    @Test("Embedding model falls back to status text when error.code is missing")
    func embeddingModel_fallsBackWhenErrorCodeMissing() async throws {
        let errorJSON: [String: Any] = [
            "error": [
                "message": "bad request from google",
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

        let model = GoogleGenerativeAIEmbeddingModel(
            modelId: GoogleGenerativeAIEmbeddingModelId(rawValue: "text-embedding-004"),
            config: GoogleGenerativeAIEmbeddingConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com",
                headers: { [:] as [String: String?] },
                fetch: fetch
            )
        )

        do {
            _ = try await model.doEmbed(options: .init(values: ["hello"]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
            #expect(error.message != "bad request from google")
            #expect(error.data == nil)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }
}
