import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

private let samplePrompt: LanguageModelV3Prompt = [
    .system(content: "You are helpful", providerOptions: nil),
    .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
]

@Suite("OpenAIChatLanguageModel")
struct OpenAIChatLanguageModelTests {
    @Test("doGenerate sends expected payload and maps response")
    func testDoGenerate() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1_711_115_037,
            "model": "gpt-4o-mini",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "content": "Hello there!",
                        "tool_calls": [
                            [
                                "id": "call-1",
                                "type": "function",
                                "function": [
                                    "name": "get_weather",
                                    "arguments": "{\"location\":\"Berlin\"}"
                                ]
                            ]
                        ],
                        "annotations": [
                            [
                                "type": "url_citation",
                                "start_index": 0,
                                "end_index": 5,
                                "url": "https://example.com",
                                "title": "Example"
                            ]
                        ]
                    ],
                    "finish_reason": "stop",
                    "logprobs": [
                        "content": [
                            [
                                "token": "Hello",
                                "logprob": -0.01,
                                "top_logprobs": [["token": "Hello", "logprob": -0.01]]
                            ]
                        ]
                    ]
                ]
            ],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 6,
                "total_tokens": 10,
                "prompt_tokens_details": ["cached_tokens": 2],
                "completion_tokens_details": [
                    "reasoning_tokens": 1,
                    "accepted_prediction_tokens": 2,
                    "rejected_prediction_tokens": 0
                ]
            ]
        ]

        let mockData = try JSONSerialization.data(withJSONObject: responseJSON)

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "x-request-id": "req-123"
                ]
            )!
            return FetchResponse(body: .data(mockData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 0) })
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                headers: ["Custom-Header": "request-header-value"]
            )
        )

        // Validate result content
        #expect(result.content.count >= 2)
        guard result.content.count >= 2 else { return }
        if case .text(let text) = result.content[0] {
            #expect(text.text == "Hello there!")
        } else {
            Issue.record("Expected text content")
        }

        let toolCallElements = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        #expect(toolCallElements.count == 1)
        #expect(toolCallElements.first?.toolCallId == "call-1")
        #expect(toolCallElements.first?.toolName == "get_weather")
        #expect(toolCallElements.first?.input == "{\"location\":\"Berlin\"}")

        let sourceElements = result.content.compactMap { content -> LanguageModelV3Source? in
            if case .source(let source) = content { return source }
            return nil
        }
        #expect(sourceElements.count == 1)

        #expect(result.finishReason == .stop)
        #expect(result.usage.inputTokens == 4)
        #expect(result.usage.outputTokens == 6)
        #expect(result.usage.totalTokens == 10)
        #expect(result.usage.reasoningTokens == 1)
        #expect(result.usage.cachedInputTokens == 2)

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata["acceptedPredictionTokens"] == .number(2))
            #expect(metadata["logprobs"] != nil)
        } else {
            Issue.record("Missing provider metadata")
        }

        // Validate request
        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request data")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-key")
        #expect(normalizedHeaders["custom-header"] == "request-header-value")
        #expect(normalizedHeaders["content-type"] == "application/json")

        #expect(json["model"] as? String == "gpt-4o-mini")
        if let messages = json["messages"] as? [[String: Any]] {
            #expect(messages.count == 2)
            #expect(messages.first?["role"] as? String == "system")
        } else {
            Issue.record("messages missing from body")
        }
    }
}
