import Foundation
import Testing
@testable import AnthropicProvider

private func regexMatches(_ regex: NSRegularExpression, _ string: String) -> Bool {
    let range = NSRange(string.startIndex..<string.endIndex, in: string)
    return regex.firstMatch(in: string, options: [], range: range) != nil
}

@Suite("AnthropicProvider supportedUrls")
struct AnthropicProviderSupportedURLsTests {
    @Test("supports image/* URLs")
    func supportsImageURLs() async throws {
        let provider = createAnthropicProvider(settings: .init(apiKey: "test-api-key"))
        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))
        let supportedUrls = try await model.supportedUrls

        let patterns = supportedUrls["image/*"]
        #expect(patterns?.isEmpty == false)

        if let regex = patterns?.first {
            #expect(regexMatches(regex, "https://example.com/image.png") == true)
        }
    }

    @Test("supports application/pdf URLs")
    func supportsPDFURLs() async throws {
        let provider = createAnthropicProvider(settings: .init(apiKey: "test-api-key"))
        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))
        let supportedUrls = try await model.supportedUrls

        let patterns = supportedUrls["application/pdf"]
        #expect(patterns?.isEmpty == false)

        if let regex = patterns?.first {
            #expect(regexMatches(regex, "https://arxiv.org/pdf/2401.00001") == true)
        }
    }
}

