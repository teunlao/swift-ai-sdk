import Foundation
import Testing
@testable import GoogleVertexProvider

@Suite("GoogleVertex supportedUrls")
struct GoogleVertexSupportedURLsTests {
    private func matches(_ regexes: [NSRegularExpression], _ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regexes.contains { regex in
            regex.firstMatch(in: value, options: [], range: range) != nil
        }
    }

    @Test("chat model supportedUrls are case-sensitive")
    func chatModelSupportedURLsAreCaseSensitive() async throws {
        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project"
        ))

        let model = provider.chat(modelId: GoogleVertexModelId(rawValue: "gemini-pro"))
        let supported = try await model.supportedUrls

        guard let patterns = supported["*"] else {
            Issue.record("Missing supported URL patterns")
            return
        }

        #expect(matches(patterns, "https://example.com/file.pdf"))
        #expect(matches(patterns, "gs://bucket/file.png"))
        #expect(matches(patterns, "HTTPS://example.com/file.pdf") == false)
        #expect(matches(patterns, "GS://bucket/file.png") == false)
    }
}
