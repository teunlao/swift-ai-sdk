import Testing
@testable import AnthropicProvider

@Suite("Anthropic placeholder")
struct AnthropicProviderPlaceholderTests {
    @Test("createAnthropicProvider throws fatal when using models")
    func placeholder() {
        _ = createAnthropicProvider()
    }
}
