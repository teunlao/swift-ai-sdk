import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import RevAIProvider

@Suite("RevAI deferred credentials", .serialized)
struct RevAIProviderAuthTests {
    @Test("A missing API key fails at generation, after provider and model construction")
    func missingAPIKey() async throws {
        let original = getenv("REVAI_API_KEY").flatMap { String(validatingCString: $0) }
        defer {
            if let original { setenv("REVAI_API_KEY", original, 1) }
            else { unsetenv("REVAI_API_KEY") }
        }
        unsetenv("REVAI_API_KEY")
        let fetch: FetchFunction = { _ in throw URLError(.userAuthenticationRequired) }
        let provider = createRevAI(settings: .init(fetch: fetch))
        let model = provider.transcription(modelId: .machine)
        await #expect(throws: LoadAPIKeyError.self) {
            try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
        }
    }
}
