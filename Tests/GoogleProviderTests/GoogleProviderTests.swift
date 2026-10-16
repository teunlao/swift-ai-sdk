import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

@Suite("Google provider public surface")
struct GoogleProviderTests {
    @Test("custom endpoint, provider headers and per-call headers reach the API")
    func customEndpoint() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let provider = await transport.provider()
        let result = try await provider.languageModel(modelId: "gemini-3.8-flash").doGenerate(options: .init(prompt: googlePrompt, headers: ["X-Request": "call"]))
        #expect(result.finishReason.unified == .stop)
        let request = try #require(await transport.captured().first)
        #expect(request.url?.absoluteString == "https://provider.example/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.value(forHTTPHeaderField: "X-Provider") == "configured")
        #expect(request.value(forHTTPHeaderField: "X-Request") == "call")
    }

    @Test("provider construction and model lookup defer authentication to the request")
    func lazyAuthentication() async throws {
        let previous = getenv("GOOGLE_GENERATIVE_AI_API_KEY").map { String(cString: $0) }
        defer {
            if let previous { setenv("GOOGLE_GENERATIVE_AI_API_KEY", previous, 1) }
            else { unsetenv("GOOGLE_GENERATIVE_AI_API_KEY") }
        }
        unsetenv("GOOGLE_GENERATIVE_AI_API_KEY")
        let provider = createGoogle()
        let model = try provider.languageModel(modelId: "gemini-3.8-flash")
        await #expect(throws: LoadAPIKeyError.self) { try await model.doGenerate(options: .init(prompt: googlePrompt)) }
    }
}
