import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google API error contracts")
struct GoogleErrorHandlingTests {
    @Test("provider errors retain status, retry classification, and details")
    func providerError() async throws {
        let payload: JSONValue = .object(["error": .object(["code": .number(429), "message": .string("quota exhausted"), "status": .string("RESOURCE_EXHAUSTED"), "details": .array([.object(["retryDelay": .string("1s")])])])])
        let transport = GoogleTransport([.init(try googleData(payload), status: 429)])
        let model = try await transport.provider().embeddingModel(modelId: "gemini-embedding-2")
        do {
            _ = try await model.doEmbed(options: .init(values: ["hello"]))
            Issue.record("expected API error")
        } catch let error as APICallError {
            #expect(error.message == "quota exhausted")
            #expect(error.statusCode == 429)
            #expect(error.isRetryable)
            let data = try #require(error.data as? GoogleErrorData)
            #expect(data.error.details == [.object(["retryDelay": .string("1s")])])
        }
    }

    @Test("malformed API payloads produce typed API errors with validation causes")
    func malformedResponse() async throws {
        let transport = GoogleTransport([.init(Data("{\"candidates\":\"not-an-array\"}".utf8))])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        do {
            _ = try await model.doGenerate(options: .init(prompt: googlePrompt))
            Issue.record("expected API error")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.cause is TypeValidationError)
        }
    }
}
