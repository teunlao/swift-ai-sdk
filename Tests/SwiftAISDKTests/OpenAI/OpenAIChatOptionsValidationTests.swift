import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAIChatOptionsValidation")
struct OpenAIChatOptionsValidationTests {
    @Test("Reject metadata keys longer than 64 characters")
    func rejectMetadataKeyTooLong() async throws {
        actor CallCounter {
            var count = 0
            func increment() { count += 1 }
            func value() -> Int { count }
        }

        let counter = CallCounter()

        let mockFetch: FetchFunction = { request in
            await counter.increment()
            let mockData = try JSONSerialization.data(withJSONObject: [
                "id": "test", "created": 1, "model": "gpt-4o-mini",
                "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
                "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
            ])
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let longKey = String(repeating: "a", count: 65)

        do {
            _ = try await model.doGenerate(
                options: LanguageModelV3CallOptions(
                    prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                    providerOptions: ["openai": [
                        "metadata": JSONValue.object([longKey: .string("value")])
                    ]]
                )
            )
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "invalid openai provider options")
            guard let typeError = error.cause as? TypeValidationError else {
                Issue.record("Expected TypeValidationError as cause")
                return
            }
            guard let schemaError = typeError.cause as? SchemaValidationIssuesError else {
                Issue.record("Expected SchemaValidationIssuesError as TypeValidationError cause")
                return
            }
            #expect(schemaError.vendor == "openai")
            #expect(
                String(describing: schemaError.issues).contains("metadata keys must be at most 64 characters"),
                "Expected metadata key validation issue"
            )
        }

        #expect(await counter.value() == 0)
    }

    @Test("Reject metadata values longer than 512 characters")
    func rejectMetadataValueTooLong() async throws {
        actor CallCounter {
            var count = 0
            func increment() { count += 1 }
            func value() -> Int { count }
        }

        let counter = CallCounter()

        let mockFetch: FetchFunction = { request in
            await counter.increment()
            let mockData = try JSONSerialization.data(withJSONObject: [
                "id": "test", "created": 1, "model": "gpt-4o-mini",
                "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
                "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
            ])
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let longValue = String(repeating: "a", count: 513)

        do {
            _ = try await model.doGenerate(
                options: LanguageModelV3CallOptions(
                    prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                    providerOptions: ["openai": [
                        "metadata": JSONValue.object(["key": .string(longValue)])
                    ]]
                )
            )
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "invalid openai provider options")
            guard let typeError = error.cause as? TypeValidationError else {
                Issue.record("Expected TypeValidationError as cause")
                return
            }
            guard let schemaError = typeError.cause as? SchemaValidationIssuesError else {
                Issue.record("Expected SchemaValidationIssuesError as TypeValidationError cause")
                return
            }
            #expect(schemaError.vendor == "openai")
            #expect(
                String(describing: schemaError.issues).contains("metadata values must be at most 512 characters"),
                "Expected metadata value validation issue"
            )
        }

        #expect(await counter.value() == 0)
    }
}
