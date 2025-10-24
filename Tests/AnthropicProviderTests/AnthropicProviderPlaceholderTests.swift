import Testing
@testable import AnthropicProvider

@Suite("Anthropic placeholder")
struct AnthropicProviderPlaceholderTests {
    @Test("createAnthropicProvider produces provider when API key supplied")
    func placeholder() throws {
        let provider = createAnthropicProvider(settings: .init(apiKey: "test-key"))
        let model = try provider.languageModel(modelId: "claude-3-opus-20240229")
        #expect(model is AnthropicMessagesLanguageModel)
    }
}
