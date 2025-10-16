import Foundation
import Testing
@testable import AISDKProvider

private struct StubLanguageModelV2: LanguageModelV2 {
    var provider: String { "stub" }
    var modelId: String { "stub-model" }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { [:] }
    }

    func doGenerate(options: LanguageModelV2CallOptions) async throws -> LanguageModelV2GenerateResult {
        LanguageModelV2GenerateResult(
            content: [.text(LanguageModelV2Text(text: ""))],
            finishReason: .stop,
            usage: LanguageModelV2Usage()
        )
    }

    func doStream(options: LanguageModelV2CallOptions) async throws -> LanguageModelV2StreamResult {
        LanguageModelV2StreamResult(
            stream: AsyncThrowingStream<LanguageModelV2StreamPart, Error> { continuation in
                continuation.finish()
            }
        )
    }
}

@Test func languageModelV2MiddlewareOverrideSupportsRegularExpressions() async throws {
    let regex = try NSRegularExpression(pattern: "https://example\\.com/.*")
    let middleware = LanguageModelV2Middleware(overrideSupportedUrls: { _ in
        ["application/json": [regex]]
    })

    let model = StubLanguageModelV2()
    guard let override = middleware.overrideSupportedUrls else {
        Issue.record("overrideSupportedUrls should be set")
        return
    }

    let urls = try await override(model)
    #expect(urls["application/json"]?.first?.pattern == regex.pattern)
}
