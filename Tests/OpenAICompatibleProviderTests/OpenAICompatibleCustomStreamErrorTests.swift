import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

@Suite("OpenAI-compatible custom stream errors")
struct OpenAICompatibleCustomStreamErrorTests {
    private struct CustomError: Codable, Sendable {
        let error: String
        let code: Int

        static let schema = FlexibleSchema(
            Schema<CustomError>.codable(
                CustomError.self,
                jsonSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("error"), .string("code")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "error": .object(["type": .string("string")]),
                        "code": .object(["type": .string("number")])
                    ])
                ])
            )
        )
    }

    private let prompt: LanguageModelV4Prompt = [
        .user(
            content: [.text(LanguageModelV4TextPart(text: "Hello"))],
            providerOptions: nil
        )
    ]

    private func makeHTTPResponse(url: URL) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
    }

    private func makeStreamBody(_ event: String) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            continuation.yield(Data("data: \(event)\n\n".utf8))
            continuation.yield(Data("data: [DONE]\n\n".utf8))
            continuation.finish()
        })
    }

    private func makeErrorConfiguration() -> OpenAICompatibleErrorConfiguration {
        OpenAICompatibleErrorConfiguration(
            errorSchema: CustomError.schema,
            errorToMessage: { "Error \($0.code): \($0.error)" },
            extractMessage: { json in
                let data = try JSONEncoder().encode(json)
                let error = try JSONDecoder().decode(CustomError.self, from: data)
                return "Error \(error.code): \(error.error)"
            }
        )
    }

    @Test("chat validates and extracts a configured stream error schema")
    func chatUsesConfiguredErrorSchema() async throws {
        let url = URL(string: "https://api.example.com/chat/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(#"{"error":"overloaded","code":4290}"#),
                urlResponse: makeHTTPResponse(url: url)
            )
        }
        let model = OpenAICompatibleChatLanguageModelV4(
            modelId: .init(rawValue: "chat-model"),
            config: .init(
                provider: "custom.chat",
                headers: { [:] },
                url: { _ in url.absoluteString },
                fetch: fetch,
                errorConfiguration: makeErrorConfiguration()
            )
        )

        let result = try await model.doStream(options: .init(prompt: prompt))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.contains(.error(error: .string("Error 4290: overloaded"))))
        guard case let .finish(reason, _, _) = parts.last else {
            Issue.record("Missing chat error finish")
            return
        }
        #expect(reason == .init(unified: .error, raw: nil))
    }

    @Test("completion validates and preserves a configured stream error payload")
    func completionUsesConfiguredErrorSchema() async throws {
        let url = URL(string: "https://api.example.com/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(#"{"error":"overloaded","code":4290}"#),
                urlResponse: makeHTTPResponse(url: url)
            )
        }
        let model = OpenAICompatibleCompletionLanguageModelV4(
            modelId: .init(rawValue: "completion-model"),
            config: .init(
                provider: "custom.completion",
                headers: { [:] },
                url: { _ in url.absoluteString },
                fetch: fetch,
                errorConfiguration: makeErrorConfiguration()
            )
        )

        let result = try await model.doStream(options: .init(prompt: prompt))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.contains(.error(error: .string("overloaded"))))
        guard case let .finish(reason, _, _) = parts.last else {
            Issue.record("Missing completion error finish")
            return
        }
        #expect(reason == .init(unified: .error, raw: nil))
    }
}
