import Foundation
import Testing
import GoogleProvider

@Suite("Google model resource paths")
struct GetModelPathTests {
    @Test("language requests preserve explicit model resources")
    func modelResources() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json")), .init(try googleFixture("text.json"))])
        let provider = await transport.provider()
        _ = try await provider.languageModel(modelId: "tunedModels/tuned-model").doGenerate(options: .init(prompt: googlePrompt))
        _ = try await provider.languageModel(modelId: "gemini-3.8-flash").doGenerate(options: .init(prompt: googlePrompt))
        let requests = await transport.captured()
        #expect(requests.map { $0.url?.path } == ["/v1beta/tunedModels/tuned-model:generateContent", "/v1beta/models/gemini-3.8-flash:generateContent"])
    }
}
