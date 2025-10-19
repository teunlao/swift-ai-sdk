import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let testPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func makeConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
    AnthropicMessagesConfig(
        provider: "anthropic.messages",
        baseURL: "https://api.anthropic.com/v1",
        headers: { [
            "x-api-key": "test-key",
            "anthropic-version": "2023-06-01"
        ] },
        fetch: fetch,
        supportedUrls: { [:] },
        generateId: { "generated-id" }
    )
}

@Suite("AnthropicMessagesLanguageModel doGenerate")
struct AnthropicMessagesLanguageModelGenerateTests {
    actor RequestCapture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    @Test("maps basic response into content, usage and metadata")
    func basicGenerate() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_123",
            "model": "claude-3-haiku-20240307",
            "content": [
                ["type": "text", "text": "Hello, World!"]
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 10
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["x-test-header": "response"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        #expect(result.finishReason == .stop)
        #expect(result.usage.inputTokens == 4)
        #expect(result.usage.outputTokens == 10)
        #expect(result.content.count == 1)
        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }

        if let metadata = result.providerMetadata?["anthropic"],
           let usage = metadata["usage"], case .object(let usageObject) = usage {
            #expect(usageObject["input_tokens"] == .number(4))
            #expect(usageObject["output_tokens"] == .number(10))
        } else {
            Issue.record("Expected usage metadata")
        }

        if let response = result.response {
            #expect(response.id == "msg_123")
            #expect(response.modelId == "claude-3-haiku-20240307")
        } else {
            Issue.record("Missing response metadata")
        }

        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["model"] as? String == "claude-3-haiku-20240307")
            #expect(json["max_tokens"] as? Int == 4096)
            #expect((json["messages"] as? [[String: Any]])?.first?["role"] as? String == "user")
        } else {
            Issue.record("Missing captured request")
        }
    }

    @Test("thinking enabled adjusts request and warnings")
    func thinkingConfiguration() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg-thinking",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": "Thoughts"]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 5,
                "output_tokens": 8,
                "cache_creation_input_tokens": 100
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let options = LanguageModelV3CallOptions(
            prompt: testPrompt,
            temperature: 0.5,
            topP: 0.9,
            topK: 50,
            providerOptions: [
                "anthropic": [
                    "thinking": .object([
                        "type": .string("enabled"),
                        "budgetTokens": .number(1000)
                    ])
                ]
            ]
        )

        let result = try await model.doGenerate(options: options)
        #expect(result.warnings.count == 3)

        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let thinking = json["thinking"] as? [String: Any] {
            #expect(thinking["type"] as? String == "enabled")
            #expect(thinking["budget_tokens"] as? Int == 1000)
        } else {
            Issue.record("Expected thinking payload")
        }
            #expect(json["max_tokens"] as? Int == 5096)
            #expect(json["temperature"] == nil)
            #expect(json["top_p"] == nil)
            #expect(json["top_k"] == nil)
        } else {
            Issue.record("Missing captured request")
        }
    }
}

@Suite("AnthropicMessagesLanguageModel doStream")
struct AnthropicMessagesLanguageModelStreamTests {
    private func makeStream(events: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data(event.utf8))
            }
            continuation.finish()
        }
    }

    @Test("streams text deltas and finish metadata")
    func streamText() async throws {
        func makeEvent(_ dictionary: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            guard let string = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "encode SSE event")
            }
            return "data: \(string)\n\n"
        }

        let events = try [
            makeEvent([
                "type": "message_start",
                "message": [
                    "id": "msg",
                    "model": "claude-3-haiku-20240307",
                    "usage": ["input_tokens": 2, "output_tokens": 0]
                ]
            ]),
            makeEvent([
                "type": "content_block_start",
                "index": 0,
                "content_block": ["type": "text", "text": ""]
            ]),
            makeEvent([
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "text_delta", "text": "Hello"]
            ]),
            makeEvent([
                "type": "content_block_stop",
                "index": 0
            ]),
            makeEvent([
                "type": "message_delta",
                "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
                "usage": ["input_tokens": 2, "output_tokens": 5]
            ]),
            makeEvent(["type": "message_stop"])
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(prompt: testPrompt))
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.contains(where: { part in
            if case .textDelta(_, let delta, _) = part { return delta == "Hello" }
            return false
        }))
        #expect(parts.contains(where: { part in
            if case .finish(let finishReason, let usage, _) = part {
                return finishReason == .stop && usage.outputTokens == 5
            }
            return false
        }))
    }
}
