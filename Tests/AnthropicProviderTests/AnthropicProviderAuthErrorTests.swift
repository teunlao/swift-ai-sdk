import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let authErrorTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private actor FetchCallCounter {
    private var count: Int = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

@Suite("AnthropicProvider auth errors", .serialized)
struct AnthropicProviderAuthErrorTests {
    @Test("missing API key throws LoadAPIKeyError at request-time (no crash)")
    func missingAPIKeyThrows() async throws {
        let original = getenv("ANTHROPIC_API_KEY").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("ANTHROPIC_API_KEY", original, 1)
            } else {
                unsetenv("ANTHROPIC_API_KEY")
            }
        }

        unsetenv("ANTHROPIC_API_KEY")

        let fetchCalls = FetchCallCounter()
        let fetch: FetchFunction = { request in
            await fetchCalls.increment()
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(Data()), urlResponse: response)
        }

        let provider = createAnthropicProvider(settings: .init(fetch: fetch))
        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))

        do {
            _ = try await model.doGenerate(options: .init(prompt: authErrorTestPrompt))
            Issue.record("Expected LoadAPIKeyError to be thrown")
        } catch let error as LoadAPIKeyError {
            #expect(error.message.contains("Anthropic API key is missing.") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await fetchCalls.value() == 0)
    }

    @Test("apiKey/authToken conflict throws InvalidArgumentError at request-time (no crash)")
    func apiKeyAuthTokenConflictThrows() async throws {
        let fetchCalls = FetchCallCounter()
        let fetch: FetchFunction = { request in
            await fetchCalls.increment()
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(Data()), urlResponse: response)
        }

        let provider = createAnthropicProvider(settings: .init(
            apiKey: "test-api-key",
            authToken: "test-auth-token",
            fetch: fetch
        ))

        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))

        do {
            _ = try await model.doGenerate(options: .init(prompt: authErrorTestPrompt))
            Issue.record("Expected InvalidArgumentError to be thrown")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "apiKey/authToken")
            #expect(
                error.message
                    == "Both apiKey and authToken were provided. Please use only one authentication method."
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await fetchCalls.value() == 0)
    }
}

