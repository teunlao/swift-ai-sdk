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

    // MARK: - Batch 1: Request Body Validation Tests

    @Test("should send the model id and settings")
    func sendsModelIdAndSettings() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": ""]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
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

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            maxOutputTokens: 100,
            temperature: 0.5,
            stopSequences: ["abc", "def"],
            topP: 0.9,
            topK: 1,
            frequencyPenalty: 0.15
        ))

        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["model"] as? String == "claude-3-haiku-20240307")
            #expect(json["max_tokens"] as? Int == 100)
            #expect(json["stop_sequences"] as? [String] == ["abc", "def"])
            #expect(json["temperature"] as? Double == 0.5)
            #expect(json["top_k"] as? Int == 1)
            #expect(json["top_p"] as? Double == 0.9)
            if let messages = json["messages"] as? [[String: Any]] {
                #expect(messages.first?["role"] as? String == "user")
            } else {
                Issue.record("Expected messages array")
            }
        } else {
            Issue.record("Missing captured request")
        }
    }

    @Test("should pass headers")
    func passesHeaders() async throws {
        actor HeaderCapture {
            var headers: [String: String]?
            func store(_ headers: [String: String]) { self.headers = headers }
            func current() -> [String: String]? { headers }
        }

        let capture = HeaderCapture()
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
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
            await capture.store(request.allHTTPHeaderFields ?? [:])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-api-key",
                "anthropic-version": "2023-06-01",
                "Custom-Provider-Header": "provider-header-value"
            ] },
            fetch: fetch,
            supportedUrls: { [:] },
            generateId: { "generated-id" }
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        if let headers = await capture.current() {
            #expect(headers["anthropic-version"] == "2023-06-01")
            #expect(headers["Content-Type"] == "application/json")
            #expect(headers["custom-provider-header"] == "provider-header-value")
            #expect(headers["custom-request-header"] == "request-header-value")
            #expect(headers["x-api-key"] == "test-api-key")
        } else {
            Issue.record("Missing captured headers")
        }
    }

    @Test("should pass tools and toolChoice")
    func passesToolsAndToolChoice() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": ""]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
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

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "value": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("value")]),
                        "additionalProperties": .bool(false),
                        "$schema": .string("http://json-schema.org/draft-07/schema#")
                    ])
                ))
            ],
            toolChoice: .tool(toolName: "test-tool")
        ))

        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["model"] as? String == "claude-3-haiku-20240307")

            if let messages = json["messages"] as? [[String: Any]] {
                #expect(messages.first?["role"] as? String == "user")
            } else {
                Issue.record("Expected messages array")
            }

            #expect(json["max_tokens"] as? Int == 4096)

            if let tools = json["tools"] as? [[String: Any]],
               let tool = tools.first {
                #expect(tool["name"] as? String == "test-tool")
                #expect(tool["input_schema"] != nil)
            } else {
                Issue.record("Expected tools array")
            }

            if let toolChoice = json["tool_choice"] as? [String: Any] {
                #expect(toolChoice["type"] as? String == "tool")
                #expect(toolChoice["name"] as? String == "test-tool")
            } else {
                Issue.record("Expected tool_choice object")
            }
        } else {
            Issue.record("Missing captured request")
        }
    }

    @Test("should pass disableParallelToolUse")
    func passesDisableParallelToolUse() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": ""]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
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

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "value": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("value")]),
                        "additionalProperties": .bool(false),
                        "$schema": .string("http://json-schema.org/draft-07/schema#")
                    ])
                ))
            ],
            providerOptions: [
                "anthropic": [
                    "disableParallelToolUse": .bool(true)
                ]
            ]
        ))

        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let toolChoice = json["tool_choice"] as? [String: Any] {
                #expect(toolChoice["type"] as? String == "auto")
                #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)
            } else {
                Issue.record("Expected tool_choice object with disable_parallel_tool_use")
            }
        } else {
            Issue.record("Missing captured request")
        }
    }

    // MARK: - Batch 2: Response Parsing Tests

    @Test("should extract text response")
    func extractsTextResponse() async throws {
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": "Hello, World!"]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        #expect(result.content.count == 1)
        if case .text(let textContent) = result.content.first {
            #expect(textContent.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("should extract tool calls")
    func extractsToolCalls() async throws {
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [
                ["type": "text", "text": "Some text\n\n"],
                [
                    "type": "tool_use",
                    "id": "toolu_1",
                    "name": "test-tool",
                    "input": ["value": "example value"]
                ]
            ],
            "stop_reason": "tool_use",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "value": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("value")]),
                        "additionalProperties": .bool(false),
                        "$schema": .string("http://json-schema.org/draft-07/schema#")
                    ])
                ))
            ]
        ))

        #expect(result.content.count == 2)
        #expect(result.finishReason == .toolCalls)

        // First element: text
        if case .text(let textContent) = result.content[0] {
            #expect(textContent.text == "Some text\n\n")
        } else {
            Issue.record("Expected text content at index 0")
        }

        // Second element: tool call
        if case .toolCall(let toolCall) = result.content[1] {
            #expect(toolCall.toolCallId == "toolu_1")
            #expect(toolCall.toolName == "test-tool")
            #expect(toolCall.input == "{\"value\":\"example value\"}")
        } else {
            Issue.record("Expected tool call at index 1")
        }
    }

    @Test("should extract usage")
    func extractsUsage() async throws {
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": ""]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 20,
                "output_tokens": 5
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == 5)
        #expect(result.usage.totalTokens == 25)
        #expect(result.usage.cachedInputTokens == nil)
    }

    @Test("should send additional response information")
    func sendsAdditionalResponseInformation() async throws {
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "test-id",
            "model": "test-model",
            "content": [["type": "text", "text": ""]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Content-Length": "203"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        #expect(result.response != nil)
        if let response = result.response {
            #expect(response.id == "test-id")
            #expect(response.modelId == "test-model")
            #expect(response.headers != nil)
            #expect(response.headers?["content-type"] == "application/json")
            #expect(response.headers?["content-length"] == "203")
        } else {
            Issue.record("Expected response metadata")
        }
    }

    @Test("should include stop_sequence in provider metadata")
    func includesStopSequenceInProviderMetadata() async throws {
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_017TfcQ4AgGxKyBduUpqYPZn",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": "Hello, World!"]],
            "stop_reason": "stop_sequence",
            "stop_sequence": "STOP",
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            stopSequences: ["STOP"]
        ))

        // Check providerMetadata matches upstream structure
        if let metadata = result.providerMetadata?["anthropic"] {
            // Check stopSequence
            if let stopSeq = metadata["stopSequence"], case .string(let stopSeqValue) = stopSeq {
                #expect(stopSeqValue == "STOP")
            } else {
                Issue.record("Expected stopSequence in metadata")
            }

            // Check usage object
            if let usage = metadata["usage"], case .object(let usageObject) = usage {
                #expect(usageObject["input_tokens"] == .number(4))
                #expect(usageObject["output_tokens"] == .number(30))
            } else {
                Issue.record("Expected usage in metadata")
            }

            // Check cacheCreationInputTokens is null (top-level)
            if let cacheTokens = metadata["cacheCreationInputTokens"], case .null = cacheTokens {
                // Expected null value
            } else {
                Issue.record("Expected cacheCreationInputTokens to be null")
            }
        } else {
            Issue.record("Expected anthropic provider metadata")
        }
    }

    // MARK: - Batch 3: Advanced Response Parsing Tests

    @Test("should extract reasoning response")
    func extractsReasoningResponse() async throws {
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [
                [
                    "type": "thinking",
                    "thinking": "I am thinking...",
                    "signature": "1234567890"
                ],
                [
                    "type": "text",
                    "text": "Hello, World!"
                ]
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 10,
                "output_tokens": 20
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        #expect(result.content.count == 2)

        // First content should be reasoning
        if case .reasoning(let reasoning) = result.content[0] {
            #expect(reasoning.text == "I am thinking...")
            if let providerMetadata = reasoning.providerMetadata,
               let anthropicMeta = providerMetadata["anthropic"],
               let signature = anthropicMeta["signature"],
               case .string(let sig) = signature {
                #expect(sig == "1234567890")
            } else {
                Issue.record("Expected signature in reasoning provider metadata")
            }
        } else {
            Issue.record("Expected first content to be reasoning, got: \(result.content[0])")
        }

        // Second content should be text
        if case .text(let text) = result.content[1] {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected second content to be text")
        }
    }

    @Test("should return the json response")
    func returnsJsonResponse() async throws {
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [
                [
                    "type": "text",
                    "text": "Some text\n\n"
                ],
                [
                    "type": "tool_use",
                    "id": "toolu_1",
                    "name": "json",
                    "input": ["name": "example value"]
                ]
            ],
            "stop_reason": "tool_use",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 10,
                "output_tokens": 20
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")])
            ]),
            "required": .array([.string("name")]),
            "additionalProperties": .bool(false)
        ])

        let result = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            responseFormat: .json(schema: schema, name: nil, description: nil)
        ))

        // JSON response format should return the tool input as text
        #expect(result.content.count == 1)
        if case .text(let text) = result.content[0] {
            #expect(text.text == "{\"name\":\"example value\"}")
        } else {
            Issue.record("Expected text content with JSON string")
        }
    }

    @Test("should expose the raw response headers")
    func exposesRawResponseHeaders() async throws {
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [
                ["type": "text", "text": "Hello!"]
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 10,
                "output_tokens": 5
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: [
                                            "content-type": "application/json",
                                            "content-length": "237",
                                            "test-header": "test-value"
                                          ])!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        // Check headers are exposed
        #expect(result.response != nil)
        if let response = result.response {
            #expect(response.headers != nil)
            #expect(response.headers?["content-type"] == "application/json")
            #expect(response.headers?["content-length"] == "237")
            #expect(response.headers?["test-header"] == "test-value")
        } else {
            Issue.record("Expected response metadata")
        }
    }

    @Test("should process PDF citation responses")
    func processesPdfCitationResponses() async throws {
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [
                [
                    "type": "text",
                    "text": "Based on the document, the results show positive growth.",
                    "citations": [
                        [
                            "type": "page_location",
                            "cited_text": "Revenue increased by 25% year over year",
                            "document_index": 0,
                            "document_title": "Financial Report 2023",
                            "start_page_number": 5,
                            "end_page_number": 6
                        ]
                    ]
                ]
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 100,
                "output_tokens": 50
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let pdfFile = LanguageModelV3FilePart(
            data: .base64("base64PDFdata"),
            mediaType: "application/pdf",
            filename: "financial-report.pdf",
            providerOptions: ["anthropic": ["citations": .object(["enabled": .bool(true)])]]
        )

        let result = try await model.doGenerate(options: .init(prompt: [
            .user(content: [
                .file(pdfFile),
                .text(.init(text: "What do the results show?"))
            ], providerOptions: nil)
        ]))

        // Should have 2 content items: text + source citation
        #expect(result.content.count == 2)

        // First should be text
        if case .text(let text) = result.content[0] {
            #expect(text.text == "Based on the document, the results show positive growth.")
        } else {
            Issue.record("Expected text content")
        }

        // Second should be source citation
        if case .source(.document(_, let mediaType, let title, _, let providerMetadata)) = result.content[1] {
            #expect(title == "Financial Report 2023")
            #expect(mediaType == "application/pdf")

            // Check provider metadata for citation details
            if let anthropicMeta = providerMetadata?["anthropic"] {
                if let citedText = anthropicMeta["citedText"], case .string(let text) = citedText {
                    #expect(text == "Revenue increased by 25% year over year")
                }
                if let startPage = anthropicMeta["startPageNumber"], case .number(let page) = startPage {
                    #expect(page == 5)
                }
                if let endPage = anthropicMeta["endPageNumber"], case .number(let page) = endPage {
                    #expect(page == 6)
                }
            } else {
                Issue.record("Expected anthropic provider metadata in source")
            }
        } else {
            Issue.record("Expected source citation content")
        }
    }

    @Test("should process text citation responses")
    func processesTextCitationResponses() async throws {
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [
                [
                    "type": "text",
                    "text": "The text shows important information.",
                    "citations": [
                        [
                            "type": "char_location",
                            "cited_text": "important information",
                            "document_index": 0,
                            "document_title": "Test Document",
                            "start_char_index": 15,
                            "end_char_index": 35
                        ]
                    ]
                ]
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 50,
                "output_tokens": 30
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let textFile = LanguageModelV3FilePart(
            data: .base64("VGVzdCBkb2N1bWVudCBjb250ZW50"),
            mediaType: "text/plain",
            filename: "test.txt",
            providerOptions: ["anthropic": ["citations": .object(["enabled": .bool(true)])]]
        )

        let result = try await model.doGenerate(options: .init(prompt: [
            .user(content: [
                .file(textFile),
                .text(.init(text: "What does this say?"))
            ], providerOptions: nil)
        ]))

        // Should have 2 content items: text + source citation
        #expect(result.content.count == 2)

        // First should be text
        if case .text(let text) = result.content[0] {
            #expect(text.text == "The text shows important information.")
        } else {
            Issue.record("Expected text content")
        }

        // Second should be source citation
        if case .source(.document(_, let mediaType, let title, _, let providerMetadata)) = result.content[1] {
            #expect(title == "Test Document")
            #expect(mediaType == "text/plain")

            // Check provider metadata for citation details
            if let anthropicMeta = providerMetadata?["anthropic"] {
                if let citedText = anthropicMeta["citedText"], case .string(let text) = citedText {
                    #expect(text == "important information")
                }
                if let startChar = anthropicMeta["startCharIndex"], case .number(let index) = startChar {
                    #expect(index == 15)
                }
                if let endChar = anthropicMeta["endCharIndex"], case .number(let index) = endChar {
                    #expect(index == 35)
                }
            } else {
                Issue.record("Expected anthropic provider metadata in source")
            }
        } else {
            Issue.record("Expected source citation content")
        }
    }

    // MARK: - Batch 4: Provider Options & Request Body Tests

    @Test("should pass json schema response format as a tool")
    func passesJsonSchemaResponseFormatAsTool() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [
                [
                    "type": "text",
                    "text": "Some text\n\n"
                ],
                [
                    "type": "tool_use",
                    "id": "toolu_1",
                    "name": "json",
                    "input": ["name": "example value"]
                ]
            ],
            "stop_reason": "tool_use",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 10,
                "output_tokens": 20
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")])
            ]),
            "required": .array([.string("name")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            responseFormat: .json(schema: schema, name: nil, description: nil)
        ))

        // Verify request body has JSON tool
        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {

            #expect(json["model"] as? String == "claude-3-haiku-20240307")
            #expect(json["max_tokens"] as? Int == 4096)

            // Check tool_choice
            if let toolChoice = json["tool_choice"] as? [String: Any] {
                #expect(toolChoice["type"] as? String == "tool")
                #expect(toolChoice["name"] as? String == "json")
                #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)
            } else {
                Issue.record("Expected tool_choice in request")
            }

            // Check tools array
            if let tools = json["tools"] as? [[String: Any]],
               let jsonTool = tools.first {
                #expect(jsonTool["name"] as? String == "json")
                #expect(jsonTool["description"] as? String == "Respond with a JSON object.")

                if let inputSchema = jsonTool["input_schema"] as? [String: Any] {
                    #expect(inputSchema["type"] as? String == "object")
                    #expect(inputSchema["$schema"] as? String == "http://json-schema.org/draft-07/schema#")
                    #expect(inputSchema["additionalProperties"] as? Bool == false)
                }
            } else {
                Issue.record("Expected json tool in tools array")
            }
        } else {
            Issue.record("Expected request body")
        }
    }

    @Test("should support cache control")
    func supportsCacheControl() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": ""]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 20,
                "output_tokens": 50,
                "cache_creation_input_tokens": 10,
                "cache_read_input_tokens": 5
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: [
            .user(
                content: [.text(.init(text: "Hello"))],
                providerOptions: [
                    "anthropic": [
                        "cacheControl": .object(["type": .string("ephemeral")])
                    ]
                ]
            )
        ]))

        // Verify cache_control in request body
        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
           let messages = json["messages"] as? [[String: Any]],
           let firstMessage = messages.first,
           let content = firstMessage["content"] as? [[String: Any]],
           let firstContent = content.first {

            if let cacheControl = firstContent["cache_control"] as? [String: Any] {
                #expect(cacheControl["type"] as? String == "ephemeral")
            } else {
                Issue.record("Expected cache_control in content")
            }
        } else {
            Issue.record("Expected valid request body")
        }

        // Verify cache tokens in response metadata
        #expect(result.providerMetadata != nil)
        if let metadata = result.providerMetadata?["anthropic"] {
            if let cacheTokens = metadata["cacheCreationInputTokens"], case .number(let tokens) = cacheTokens {
                #expect(tokens == 10)
            }

            if let usage = metadata["usage"], case .object(let usageObj) = usage {
                #expect(usageObj["cache_creation_input_tokens"] == .number(10))
                #expect(usageObj["cache_read_input_tokens"] == .number(5))
                #expect(usageObj["input_tokens"] == .number(20))
                #expect(usageObj["output_tokens"] == .number(50))
            }
        } else {
            Issue.record("Expected anthropic provider metadata")
        }
    }

    @Test("should support cache control and return extra fields in provider metadata")
    func supportsCacheControlWithTTL() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": ""]],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 20,
                "output_tokens": 50,
                "cache_creation_input_tokens": 10,
                "cache_read_input_tokens": 5,
                "cache_creation": [
                    "ephemeral_5m_input_tokens": 0,
                    "ephemeral_1h_input_tokens": 10
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: [
            .user(
                content: [.text(.init(text: "Hello"))],
                providerOptions: [
                    "anthropic": [
                        "cacheControl": .object([
                            "type": .string("ephemeral"),
                            "ttl": .string("1h")
                        ])
                    ]
                ]
            )
        ]))

        // Verify cache_control with TTL in request body
        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
           let messages = json["messages"] as? [[String: Any]],
           let firstMessage = messages.first,
           let content = firstMessage["content"] as? [[String: Any]],
           let firstContent = content.first {

            if let cacheControl = firstContent["cache_control"] as? [String: Any] {
                #expect(cacheControl["type"] as? String == "ephemeral")
                #expect(cacheControl["ttl"] as? String == "1h")
            } else {
                Issue.record("Expected cache_control with ttl in content")
            }
        } else {
            Issue.record("Expected valid request body")
        }

        // Verify extra cache fields in response metadata
        #expect(result.providerMetadata != nil)
        if let metadata = result.providerMetadata?["anthropic"] {
            if let usage = metadata["usage"], case .object(let usageObj) = usage {
                // Check cache_creation field
                if let cacheCreation = usageObj["cache_creation"], case .object(let creation) = cacheCreation {
                    #expect(creation["ephemeral_5m_input_tokens"] == .number(0))
                    #expect(creation["ephemeral_1h_input_tokens"] == .number(10))
                } else {
                    Issue.record("Expected cache_creation in usage")
                }
            }
        } else {
            Issue.record("Expected anthropic provider metadata")
        }
    }

    // MARK: - Batch 5: Basic Request & Error Handling Tests

    @Test("should send request body")
    func sendsRequestBody() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-haiku-20240307",
            "content": [],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 20,
                "output_tokens": 50
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(prompt: [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]))

        // Verify request body structure
        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {

            #expect(json["model"] as? String == "claude-3-haiku-20240307")
            #expect(json["max_tokens"] as? Int == 4096)

            if let messages = json["messages"] as? [[String: Any]],
               let firstMessage = messages.first {
                #expect(firstMessage["role"] as? String == "user")

                if let content = firstMessage["content"] as? [[String: Any]],
                   let firstContent = content.first {
                    #expect(firstContent["type"] as? String == "text")
                    #expect(firstContent["text"] as? String == "Hello")

                    // cache_control should not be present (or undefined/null)
                    let hasCacheControl = firstContent["cache_control"] != nil
                    #expect(hasCacheControl == false)
                }
            }

            // Optional fields should not be present (or be null/undefined equivalent)
            #expect((json["system"] as? NSNull) != nil || json["system"] == nil)
            #expect((json["temperature"] as? NSNull) != nil || json["temperature"] == nil)
            #expect((json["top_p"] as? NSNull) != nil || json["top_p"] == nil)
            #expect((json["top_k"] as? NSNull) != nil || json["top_k"] == nil)
            #expect((json["stop_sequences"] as? NSNull) != nil || json["stop_sequences"] == nil)
            #expect((json["tool_choice"] as? NSNull) != nil || json["tool_choice"] == nil)
            #expect((json["tools"] as? NSNull) != nil || json["tools"] == nil)
        } else {
            Issue.record("Expected valid request body")
        }
    }

    @Test("should throw an api error when the server is overloaded")
    func throwsApiErrorWhenOverloaded() async throws {
        let errorJSON = """
        {"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"}}
        """
        let errorData = errorJSON.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 529,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "application/json"])!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(errorData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        // Verify the error message contains "Overloaded"
        do {
            _ = try await model.doGenerate(options: .init(prompt: [
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ]))
            Issue.record("Expected error to be thrown")
        } catch {
            let errorMessage = String(describing: error)
            #expect(errorMessage.contains("Overloaded"))
        }
    }
}

@Suite("AnthropicMessagesLanguageModel doStream")
struct AnthropicMessagesLanguageModelStreamTests {
    actor RequestCapture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func makeStream(events: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data((event + "\n\n").utf8))
            }
            continuation.finish()
        }
    }

    private func makeConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
        AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-api-key",
                "anthropic-version": "2023-06-01"
            ] },
            fetch: fetch
        )
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

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))
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

    // MARK: - Batch 6: Basic Streaming Tests

    @Test("should pass the messages and the model")
    func passesMessagesAndModel() async throws {
        let capture = RequestCapture()
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello, World!\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "text/event-stream"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doStream(options: LanguageModelV3CallOptions(prompt: [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]))

        // Verify request body
        if let request = await capture.current(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {

            #expect(json["stream"] as? Bool == true)
            #expect(json["model"] as? String == "claude-3-haiku-20240307")
            #expect(json["max_tokens"] as? Int == 4096)

            if let messages = json["messages"] as? [[String: Any]],
               let firstMessage = messages.first {
                #expect(firstMessage["role"] as? String == "user")
                if let content = firstMessage["content"] as? [[String: Any]],
                   let firstContent = content.first {
                    #expect(firstContent["type"] as? String == "text")
                    #expect(firstContent["text"] as? String == "Hello")
                }
            }
        } else {
            Issue.record("Expected valid request body")
        }
    }

    @Test("should pass headers")
    func passesHeaders() async throws {
        let capture = RequestCapture()
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello, World!\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "text/event-stream"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-api-key",
                "anthropic-version": "2023-06-01",
                "custom-provider-header": "provider-header-value"
            ] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        // Verify headers
        if let request = await capture.current() {
            #expect(request.allHTTPHeaderFields?["custom-provider-header"] == "provider-header-value")
            #expect(request.allHTTPHeaderFields?["custom-request-header"] == "request-header-value")
            #expect(request.allHTTPHeaderFields?["x-api-key"] == "test-api-key")
            #expect(request.allHTTPHeaderFields?["anthropic-version"] == "2023-06-01")
            #expect(request.allHTTPHeaderFields?["Content-Type"] == "application/json")
        } else {
            Issue.record("Expected valid request")
        }
    }

    @Test("should stream text deltas")
    func streamsTextDeltas() async throws {
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\", \"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"World!\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["content-type": "text/event-stream"])!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify stream-start
        #expect(parts.contains(where: { part in
            if case .streamStart = part { return true }
            return false
        }))

        // Verify response-metadata
        #expect(parts.contains(where: { part in
            if case .responseMetadata(let id, let modelId, _) = part {
                return id == "msg_123" && modelId == "claude-3-haiku-20240307"
            }
            return false
        }))

        // Verify text-start
        #expect(parts.contains(where: { part in
            if case .textStart = part { return true }
            return false
        }))

        // Verify text deltas in order
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["Hello", ", ", "World!"])

        // Verify text-end
        #expect(parts.contains(where: { part in
            if case .textEnd = part { return true }
            return false
        }))

        // Verify finish
        #expect(parts.contains(where: { part in
            if case .finish(let finishReason, let usage, _) = part {
                return finishReason == .stop && usage.inputTokens == 17 && usage.outputTokens == 227
            }
            return false
        }))
    }

    @Test("should send request body")
    func sendsStreamRequestBody() async throws {
        let capture = RequestCapture()
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_01KfpJoAEabmH2iHRRFjQMAG\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello, World!\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["test-header": "test-value"])!

        let config = makeConfig { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        if let request = await capture.current(),
           let bodyData = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            // Verify stream: true
            #expect(json["stream"] as? Bool == true)
            // Verify model and max_tokens
            #expect(json["model"] as? String == "claude-3-haiku-20240307")
            #expect(json["max_tokens"] as? Int == 4096)
            // Verify messages structure
            if let messages = json["messages"] as? [[String: Any]],
               let firstMessage = messages.first {
                #expect(firstMessage["role"] as? String == "user")
                if let content = firstMessage["content"] as? [[String: Any]],
                   let firstContent = content.first {
                    #expect(firstContent["type"] as? String == "text")
                    #expect(firstContent["text"] as? String == "Hello")
                }
            }
            // Verify optional fields are absent
            #expect((json["system"] as? NSNull) != nil || json["system"] == nil)
            #expect((json["temperature"] as? NSNull) != nil || json["temperature"] == nil)
            #expect((json["top_p"] as? NSNull) != nil || json["top_p"] == nil)
            #expect((json["top_k"] as? NSNull) != nil || json["top_k"] == nil)
            #expect((json["stop_sequences"] as? NSNull) != nil || json["stop_sequences"] == nil)
            #expect((json["tool_choice"] as? NSNull) != nil || json["tool_choice"] == nil)
            #expect((json["tools"] as? NSNull) != nil || json["tools"] == nil)
        } else {
            Issue.record("Expected valid request with body")
        }
    }

    @Test("should handle stop_reason:pause_turn")
    func handlesPauseTurn() async throws {
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_01KfpJoAEabmH2iHRRFjQMAG\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\", \"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"World!\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"pause_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let config = makeConfig { _ in
            FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify finish with stop reason (pause_turn maps to stop)
        let finishParts = parts.filter { part in
            if case .finish = part { return true }
            return false
        }
        #expect(finishParts.count == 1)

        if case .finish(let finishReason, let usage, let providerMetadata) = finishParts[0] {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 17)
            #expect(usage.outputTokens == 227)
            #expect(usage.totalTokens == 244)

            // Verify provider metadata
            if let providerMetadata = providerMetadata,
               let metaObj = providerMetadata["anthropic"] {
                #expect(metaObj["cacheCreationInputTokens"] == JSONValue.null)
                #expect(metaObj["stopSequence"] == JSONValue.null)
                if case .object(let usageObj) = metaObj["usage"] {
                    #expect(usageObj["input_tokens"] == JSONValue.number(17))
                    #expect(usageObj["output_tokens"] == JSONValue.number(227))
                }
            }
        } else {
            Issue.record("Expected finish part")
        }
    }

    @Test("should include stop_sequence in provider metadata")
    func includesStopSequenceInMetadata() async throws {
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_01KfpJoAEabmH2iHRRFjQMAG\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"STOP\"},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let config = makeConfig { _ in
            FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            stopSequences: ["STOP"]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify finish with stop_sequence metadata
        let finishParts = parts.filter { part in
            if case .finish = part { return true }
            return false
        }
        #expect(finishParts.count == 1)

        if case .finish(let finishReason, let usage, let providerMetadata) = finishParts[0] {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 17)
            #expect(usage.outputTokens == 227)
            #expect(usage.totalTokens == 244)

            // Verify provider metadata includes stopSequence
            if let providerMetadata = providerMetadata,
               let metaObj = providerMetadata["anthropic"] {
                #expect(metaObj["cacheCreationInputTokens"] == JSONValue.null)
                #expect(metaObj["stopSequence"] == JSONValue.string("STOP"))
                if case .object(let usageObj) = metaObj["usage"] {
                    #expect(usageObj["input_tokens"] == JSONValue.number(17))
                    #expect(usageObj["output_tokens"] == JSONValue.number(227))
                }
            }
        } else {
            Issue.record("Expected finish part")
        }
    }

    @Test("should support cache control")
    func supportsCacheControlInStreaming() async throws {
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_01KfpJoAEabmH2iHRRFjQMAG\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1,\"cache_creation_input_tokens\":10,\"cache_read_input_tokens\":5}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\": \"ping\"}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let config = makeConfig { _ in
            FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify finish with cache metadata
        let finishParts = parts.filter { part in
            if case .finish = part { return true }
            return false
        }
        #expect(finishParts.count == 1)

        if case .finish(let finishReason, let usage, let providerMetadata) = finishParts[0] {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 17)
            #expect(usage.outputTokens == 227)
            #expect(usage.totalTokens == 244)
            #expect(usage.cachedInputTokens == 5)

            // Verify provider metadata includes cache tokens
            if let providerMetadata = providerMetadata,
               let metaObj = providerMetadata["anthropic"] {
                #expect(metaObj["cacheCreationInputTokens"] == JSONValue.number(10))
                #expect(metaObj["stopSequence"] == JSONValue.null)
                if case .object(let usageObj) = metaObj["usage"] {
                    #expect(usageObj["cache_creation_input_tokens"] == JSONValue.number(10))
                    #expect(usageObj["cache_read_input_tokens"] == JSONValue.number(5))
                    #expect(usageObj["input_tokens"] == JSONValue.number(17))
                    #expect(usageObj["output_tokens"] == JSONValue.number(227))
                }
            }
        } else {
            Issue.record("Expected finish part")
        }
    }

    @Test("should support cache control and return extra fields in provider metadata")
    func supportsCacheControlWithExtraFields() async throws {
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_01KfpJoAEabmH2iHRRFjQMAG\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1,\"cache_creation_input_tokens\":10,\"cache_read_input_tokens\":5,\"cache_creation\":{\"ephemeral_5m_input_tokens\":0,\"ephemeral_1h_input_tokens\":10}}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\": \"ping\"}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let config = makeConfig { _ in
            FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify finish with cache_creation metadata
        let finishParts = parts.filter { part in
            if case .finish = part { return true }
            return false
        }
        #expect(finishParts.count == 1)

        if case .finish(let finishReason, let usage, let providerMetadata) = finishParts[0] {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 17)
            #expect(usage.outputTokens == 227)
            #expect(usage.cachedInputTokens == 5)

            // Verify provider metadata includes cache_creation
            if let providerMetadata = providerMetadata,
               let metaObj = providerMetadata["anthropic"] {
                #expect(metaObj["cacheCreationInputTokens"] == JSONValue.number(10))
                if case .object(let usageObj) = metaObj["usage"] {
                    #expect(usageObj["cache_creation_input_tokens"] == JSONValue.number(10))
                    #expect(usageObj["cache_read_input_tokens"] == JSONValue.number(5))
                    // Verify cache_creation nested object
                    if let cacheCreation = usageObj["cache_creation"], case .object(let cacheCreationObj) = cacheCreation {
                        #expect(cacheCreationObj["ephemeral_5m_input_tokens"] == JSONValue.number(0))
                        #expect(cacheCreationObj["ephemeral_1h_input_tokens"] == JSONValue.number(10))
                    } else {
                        Issue.record("Expected cache_creation object in usage. Got: \(usageObj.keys.sorted())")
                    }
                }
            }
        } else {
            Issue.record("Expected finish part")
        }
    }

    @Test("should process PDF citation responses in streaming")
    func processesPDFCitationsInStreaming() async throws {
        let events = [
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_01KfpJoAEabmH2iHRRFjQMAG\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-haiku-20240307\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":17,\"output_tokens\":1}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Based on the document\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\", results show growth.\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"citations_delta\",\"citation\":{\"type\":\"page_location\",\"cited_text\":\"Revenue increased by 25% year over year\",\"document_index\":0,\"document_title\":\"Financial Report 2023\",\"start_page_number\":5,\"end_page_number\":6}}}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":227}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n"
        ]

        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let config = makeConfig { _ in
            FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        let pdfFile = LanguageModelV3FilePart(
            data: .base64("base64PDFdata"),
            mediaType: "application/pdf",
            filename: "financial-report.pdf",
            providerOptions: ["anthropic": ["citations": JSONValue.object(["enabled": JSONValue.bool(true)])]]
        )

        let result = try await model.doStream(options: .init(
            prompt: [
                .user(content: [
                    .file(pdfFile),
                    .text(.init(text: "What do the results show?"))
                ], providerOptions: nil)
            ]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify text deltas
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["Based on the document", ", results show growth."])

        // Verify source (citation)
        let sources = parts.compactMap { part -> LanguageModelV3Source? in
            if case .source(let source) = part { return source }
            return nil
        }
        #expect(sources.count == 1)

        if let source = sources.first,
           case .document(let id, let mediaType, let title, let filename, let providerMetadata) = source {
            #expect(mediaType == "application/pdf")
            #expect(title == "Financial Report 2023")
            #expect(filename == "financial-report.pdf")

            // Verify citation metadata
            if let providerMetadata = providerMetadata,
               let anthropicMeta = providerMetadata["anthropic"],
               case .object(let citationObj) = anthropicMeta["citation"] {
                #expect(citationObj["type"] == JSONValue.string("page_location"))
                #expect(citationObj["cited_text"] == JSONValue.string("Revenue increased by 25% year over year"))
                #expect(citationObj["document_index"] == JSONValue.number(0))
                #expect(citationObj["start_page_number"] == JSONValue.number(5))
                #expect(citationObj["end_page_number"] == JSONValue.number(6))
            }
        } else {
            Issue.record("Expected document source with page location citation")
        }

        // Verify finish
        #expect(parts.contains(where: { part in
            if case .finish(let finishReason, _, _) = part {
                return finishReason == .stop
            }
            return false
        }))
    }

}

// MARK: - Batch 9-12: Advanced Streaming Tests

@Suite("AnthropicMessagesLanguageModel advanced streaming")
struct AnthropicMessagesLanguageModelStreamAdvancedBatch2Tests {
    actor RequestCapture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func get() -> URLRequest? { request }
    }

    private func makeStream(events: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data((event + "\n\n").utf8))
            }
            continuation.finish()
        }
    }

    private func makeConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
        AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-api-key",
                "anthropic-version": "2023-06-01"
            ] },
            fetch: fetch
        )
    }

    // MARK: - Batch 9: JSON Schema Response Format + Reasoning Deltas

    @Test("should pass json schema response format as a tool")
    func passesJsonSchemaResponseFormatAsTool() async throws {
        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01GouTqNCGXzrj5LQ5jEkw67","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_sequence":null,"usage":{"input_tokens":441,"output_tokens":2},"content":[],"stop_reason":null}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type": "ping"}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Okay"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01DBsB4vvYLnBDzZ5rBSxSLs","name":"json","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"value"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\":"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Spark"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"le"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" Day\"}"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":65}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let schema = JSONValue.object([:])
        _ = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            responseFormat: .json(schema: schema, name: nil, description: nil)
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]

        // Verify stream:true
        #expect(json["stream"] as? Bool == true)

        // Verify tool_choice
        if let toolChoice = json["tool_choice"] as? [String: Any] {
            #expect(toolChoice["type"] as? String == "tool")
            #expect(toolChoice["name"] as? String == "json")
            #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)
        }

        // Verify tools array contains json tool
        if let tools = json["tools"] as? [[String: Any]] {
            #expect(tools.count == 1)
            let jsonTool = tools[0]
            #expect(jsonTool["name"] as? String == "json")
            #expect(jsonTool["description"] as? String == "Respond with a JSON object.")
        }
    }

    @Test("should stream the response")
    func streamsJsonSchemaResponse() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01GouTqNCGXzrj5LQ5jEkw67","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_sequence":null,"usage":{"input_tokens":441,"output_tokens":2},"content":[],"stop_reason":null}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type": "ping"}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Okay"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01DBsB4vvYLnBDzZ5rBSxSLs","name":"json","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"value"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\":"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Spark"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"le"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" Day\"}"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":65}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let schema = JSONValue.object([:])
        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            responseFormat: .json(schema: schema, name: nil, description: nil)
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify response-metadata
        #expect(parts.contains(where: { (part: LanguageModelV3StreamPart) -> Bool in
            if case .responseMetadata(let id, let modelId, _) = part {
                return id == "msg_01GouTqNCGXzrj5LQ5jEkw67" && modelId == "claude-3-haiku-20240307"
            }
            return false
        }))

        // Verify text deltas for JSON content (represented as text in json response format)
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas.contains(""))
        #expect(textDeltas.contains("{\"value"))
        #expect(textDeltas.contains("\"Spark"))
        #expect(textDeltas.contains("le"))
        #expect(textDeltas.contains(" Day\"}"))

        // Verify finish reason is stop (tool_use is converted to stop for json format)
        #expect(parts.contains(where: { part in
            if case .finish(let finishReason, _, _) = part {
                return finishReason == .stop
            }
            return false
        }))
    }

    @Test("should stream reasoning deltas")
    func streamsReasoningDeltas() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"I am"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"thinking..."}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"1234567890"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify reasoning deltas
        let reasoningDeltas = parts.compactMap { part -> String? in
            if case .reasoningDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(reasoningDeltas == ["I am", "thinking...", ""])

        // Verify signature in reasoning delta
        #expect(parts.contains(where: { part in
            if case .reasoningDelta(_, let delta, let metadata) = part {
                if delta == "", let meta = metadata,
                   let metaObj = meta["anthropic"] {
                    return metaObj["signature"] == JSONValue.string("1234567890")
                }
            }
            return false
        }))

        // Verify text delta
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["Hello, World!"])

        // Verify finish
        #expect(parts.contains(where: { part in
            if case .finish(let finishReason, let usage, _) = part {
                return finishReason == .stop && usage.inputTokens == 17 && usage.outputTokens == 227
            }
            return false
        }))
    }

    // MARK: - Batch 10: Redacted Reasoning + Signature Ignoring + Tool Deltas

    @Test("should stream redacted reasoning")
    func streamsRedactedReasoning() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"redacted_thinking","data":"redacted-thinking-data"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify reasoning-start with redactedData in providerMetadata
        #expect(parts.contains(where: { part in
            if case .reasoningStart(_, let metadata) = part {
                if let meta = metadata,
                   let metaObj = meta["anthropic"] {
                    return metaObj["redactedData"] == JSONValue.string("redacted-thinking-data")
                }
            }
            return false
        }))

        // Verify reasoning-end (no deltas for redacted)
        #expect(parts.contains(where: { part in
            if case .reasoningEnd = part { return true }
            return false
        }))

        // Verify text delta
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["Hello, World!"])
    }

    @Test("should ignore signatures on text deltas")
    func ignoresSignaturesOnTextDeltas() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"1234567890"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify text delta (signature should be ignored on text blocks)
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["Hello, World!"])

        // Verify no signature in metadata (signatures on text blocks are ignored)
        for part in parts {
            if case .textDelta(_, _, let metadata) = part {
                if let meta = metadata,
                   let metaObj = meta["anthropic"] {
                    #expect(metaObj["signature"] == nil)
                }
            }
        }

        // Verify finish
        #expect(parts.contains(where: { part in
            if case .finish(let finishReason, _, _) = part {
                return finishReason == .stop
            }
            return false
        }))
    }

    @Test("should stream tool deltas")
    func streamsToolDeltas() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01GouTqNCGXzrj5LQ5jEkw67","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_sequence":null,"usage":{"input_tokens":441,"output_tokens":2},"content":[],"stop_reason":null}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type": "ping"}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Okay"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01DBsB4vvYLnBDzZ5rBSxSLs","name":"test-tool","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"value"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\":"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Spark"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"le"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" Day\"}"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":65}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let testTool = LanguageModelV3FunctionTool(
            name: "test-tool",
            inputSchema: .object([:]),
            description: nil,
            providerOptions: nil
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [.function(testTool)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify text deltas
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["Okay", "!"])

        // Verify tool-input-start
        #expect(parts.contains(where: { (part: LanguageModelV3StreamPart) -> Bool in
            if case .toolInputStart(let id, let toolName, _, _) = part {
                return id == "toolu_01DBsB4vvYLnBDzZ5rBSxSLs" && toolName == "test-tool"
            }
            return false
        }))

        // Verify tool-input-delta
        let toolDeltas = parts.compactMap { (part: LanguageModelV3StreamPart) -> String? in
            if case .toolInputDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(toolDeltas.contains(""))
        #expect(toolDeltas.contains("{\"value"))
        #expect(toolDeltas.contains("\"Spark"))
        #expect(toolDeltas.contains("le"))

        // Verify tool-call
        #expect(parts.contains(where: { part in
            if case .toolCall(let toolCall) = part {
                return toolCall.toolCallId == "toolu_01DBsB4vvYLnBDzZ5rBSxSLs" &&
                       toolCall.toolName == "test-tool" &&
                       toolCall.input == "{\"value\":\"Sparkle Day\"}"
            }
            return false
        }))

        // Verify finish reason is tool-calls
        #expect(parts.contains(where: { part in
            if case .finish(let finishReason, _, _) = part {
                return finishReason == .toolCalls
            }
            return false
        }))
    }

    // MARK: - Batch 11: Error Handling + Raw Response Headers + Raw Chunks

    @Test("should forward error chunks")
    func forwardsErrorChunks() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type": "ping"}"#,
            #"data: {"type":"error","error":{"type":"error","message":"test error"}}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify response-metadata
        #expect(parts.contains(where: { (part: LanguageModelV3StreamPart) -> Bool in
            if case .responseMetadata(let id, _, _) = part {
                return id == "msg_01KfpJoAEabmH2iHRRFjQMAG"
            }
            return false
        }))

        // Verify text-start
        #expect(parts.contains(where: { part in
            if case .textStart = part { return true }
            return false
        }))

        // Verify error chunk
        #expect(parts.contains(where: { part in
            if case .error(let error) = part {
                return String(describing: error).contains("test error")
            }
            return false
        }))
    }

    @Test("should expose the raw response headers")
    func exposesRawResponseHeaders() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["test-header": "test-value"])!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        // Verify response headers
        if let headers = result.response?.headers {
            #expect(headers["test-header"] == "test-value")
        } else {
            Issue.record("Expected response headers")
        }
    }

    @Test("should include raw chunks when includeRawChunks is enabled")
    func includesRawChunksWhenEnabled() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: true
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify raw chunks are included
        let rawParts = parts.compactMap { part -> JSONValue? in
            if case .raw(let rawValue) = part { return rawValue }
            return nil
        }
        #expect(rawParts.count > 0)

        // Verify raw chunks contain expected event types
        let rawTypes = rawParts.compactMap { rawValue -> String? in
            if case .object(let obj) = rawValue,
               case .string(let type) = obj["type"] {
                return type
            }
            return nil
        }
        #expect(rawTypes.contains("message_start"))
        #expect(rawTypes.contains("content_block_start"))
        #expect(rawTypes.contains("content_block_delta"))
        #expect(rawTypes.contains("message_delta"))
    }

    // MARK: - Batch 12: Raw Chunks Disabled + Error Tests

    @Test("should not include raw chunks when includeRawChunks is false")
    func doesNotIncludeRawChunksWhenDisabled() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
            // includeRawChunks defaults to false
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify no raw chunks
        let rawParts = parts.compactMap { part -> JSONValue? in
            if case .raw(let rawValue) = part { return rawValue }
            return nil
        }
        #expect(rawParts.count == 0)
    }

    @Test("should throw an api error when the server is overloaded")
    func throwsApiErrorWhenOverloaded() async throws {
        let fetch: FetchFunction = { _ in
            throw APICallError(
                message: "Overloaded",
                url: "",
                requestBodyValues: nil,
                statusCode: 529,
                responseHeaders: [:],
                responseBody: nil,
                cause: nil,
                isRetryable: true,
                data: nil
            )
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        do {
            _ = try await model.doStream(options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
            ))
            Issue.record("Expected APICallError to be thrown")
        } catch {
            // Verify error message contains "Overloaded"
            #expect(String(describing: error).contains("Overloaded"))
        }
    }

    @Test("should forward overloaded error during streaming")
    func forwardsOverloadedErrorDuringStreaming() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events: [String] = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"}}"#
        ]

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify we got text delta before error
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["Hello"])

        // Verify error chunk with "Overloaded" message
        #expect(parts.contains(where: { part in
            if case .error(let error) = part {
                return String(describing: error).contains("Overloaded")
            }
            return false
        }))
    }
}

// MARK: - Batch 13: Thinking Config + API Errors

@Suite("AnthropicMessagesLanguageModel thinking and errors")
struct AnthropicMessagesLanguageModelThinkingAndErrorsTests {

    @Test("should pass thinking config; add budget tokens; clear out temperature, top_p, top_k; and return warnings")
    func passesThinkingConfigAndReturnsWarnings() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Hello, World!"}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            temperature: 0.5,
            topP: 0.7,
            topK: 10,
            providerOptions: [
                "anthropic": [
                    "thinking": .object([
                        "type": .string("enabled"),
                        "budgetTokens": .number(1000)
                    ])
                ]
            ]
        ))

        // Verify request body
        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "claude-3-haiku-20240307")
        #expect(json?["max_tokens"] as? Int == 4096 + 1000)  // maxTokens + budgetTokens

        if let thinking = json?["thinking"] as? [String: Any] {
            #expect(thinking["type"] as? String == "enabled")
            #expect(thinking["budget_tokens"] as? Int == 1000)
        } else {
            Issue.record("thinking field not found")
        }

        // temperature, topP, topK should NOT be in request (cleared when thinking enabled)
        #expect(json?["temperature"] == nil)
        #expect(json?["top_p"] == nil)
        #expect(json?["top_k"] == nil)

        // Verify warnings
        #expect(result.warnings.count == 3)
        #expect(result.warnings.contains(where: {
            if case .unsupportedSetting(let setting, _) = $0 { return setting == "temperature" }
            return false
        }))
        #expect(result.warnings.contains(where: {
            if case .unsupportedSetting(let setting, _) = $0 { return setting == "topK" }
            return false
        }))
        #expect(result.warnings.contains(where: {
            if case .unsupportedSetting(let setting, _) = $0 { return setting == "topP" }
            return false
        }))
    }

    @Test("should throw an api error when the server is overloaded")
    func throwsApiErrorWhenOverloadedDoGenerate() async throws {
        let errorBody = """
        {"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"}}
        """

        let fetch: FetchFunction = { _ in
            throw APICallError(
                message: "Overloaded",
                url: "https://api.anthropic.com/v1/messages",
                requestBodyValues: nil,
                statusCode: 529,
                responseHeaders: [:],
                responseBody: errorBody,
                cause: nil,
                isRetryable: true,
                data: nil
            )
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        do {
            _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
            ))
            Issue.record("Expected APICallError to be thrown")
        } catch {
            // Verify error message contains "Overloaded"
            #expect(String(describing: error).contains("Overloaded"))
        }
    }
}

// MARK: - Batch 14: Web Search Tool Tests

@Suite("AnthropicMessagesLanguageModel web search")
struct AnthropicMessagesLanguageModelWebSearchTests {

    @Test("should enable server-side web search when using anthropic.tools.webSearch_20250305")
    func enablesServerSideWebSearch() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Here are the latest quantum computing breakthroughs."}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "What is the latest news?"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.web_search_20250305",
                    name: "web_search",
                    args: [
                        "maxUses": .number(3),
                        "allowedDomains": .array([.string("arxiv.org"), .string("nature.com"), .string("mit.edu")])
                    ]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        guard let tools = json?["tools"] as? [[String: Any]], tools.count == 1 else {
            Issue.record("Expected 1 tool in request")
            return
        }

        let tool = tools[0]
        #expect(tool["type"] as? String == "web_search_20250305")
        #expect(tool["name"] as? String == "web_search")
        #expect(tool["max_uses"] as? Int == 3)

        if let allowedDomains = tool["allowed_domains"] as? [String] {
            #expect(allowedDomains == ["arxiv.org", "nature.com", "mit.edu"])
        } else {
            Issue.record("allowed_domains not found")
        }
    }

    @Test("should pass web search configuration with blocked domains")
    func passesWebSearchConfigWithBlockedDomains() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Here are the latest stock market trends."}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "What is the latest news?"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.web_search_20250305",
                    name: "web_search",
                    args: [
                        "maxUses": .number(2),
                        "blockedDomains": .array([.string("reddit.com")])
                    ]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        guard let tools = json?["tools"] as? [[String: Any]], tools.count == 1 else {
            Issue.record("Expected 1 tool in request")
            return
        }

        let tool = tools[0]
        #expect(tool["type"] as? String == "web_search_20250305")
        #expect(tool["name"] as? String == "web_search")
        #expect(tool["max_uses"] as? Int == 2)

        if let blockedDomains = tool["blocked_domains"] as? [String] {
            #expect(blockedDomains == ["reddit.com"])
        } else {
            Issue.record("blocked_domains not found")
        }
    }

    @Test("should handle web search with user location")
    func handlesWebSearchWithUserLocation() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Here are local tech events."}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "What is the latest news?"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.web_search_20250305",
                    name: "web_search",
                    args: [
                        "maxUses": .number(1),
                        "userLocation": .object([
                            "type": .string("approximate"),
                            "city": .string("New York"),
                            "region": .string("New York"),
                            "country": .string("US"),
                            "timezone": .string("America/New_York")
                        ])
                    ]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        guard let tools = json?["tools"] as? [[String: Any]], tools.count == 1 else {
            Issue.record("Expected 1 tool in request")
            return
        }

        let tool = tools[0]
        #expect(tool["type"] as? String == "web_search_20250305")
        #expect(tool["name"] as? String == "web_search")
        #expect(tool["max_uses"] as? Int == 1)

        if let userLocation = tool["user_location"] as? [String: Any] {
            #expect(userLocation["type"] as? String == "approximate")
            #expect(userLocation["city"] as? String == "New York")
            #expect(userLocation["region"] as? String == "New York")
            #expect(userLocation["country"] as? String == "US")
            #expect(userLocation["timezone"] as? String == "America/New_York")
        } else {
            Issue.record("user_location not found")
        }
    }

    @Test("should handle web search with partial user location (city + country)")
    func handlesWebSearchWithPartialUserLocation() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Here are local events."}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "What is the latest news?"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.web_search_20250305",
                    name: "web_search",
                    args: [
                        "maxUses": .number(1),
                        "userLocation": .object([
                            "type": .string("approximate"),
                            "city": .string("London"),
                            "country": .string("GB")
                        ])
                    ]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        guard let tools = json?["tools"] as? [[String: Any]], tools.count == 1 else {
            Issue.record("Expected 1 tool in request")
            return
        }

        let tool = tools[0]
        #expect(tool["type"] as? String == "web_search_20250305")
        #expect(tool["name"] as? String == "web_search")
        #expect(tool["max_uses"] as? Int == 1)

        if let userLocation = tool["user_location"] as? [String: Any] {
            #expect(userLocation["type"] as? String == "approximate")
            #expect(userLocation["city"] as? String == "London")
            #expect(userLocation["country"] as? String == "GB")
            // region and timezone should not be present
            #expect(userLocation["region"] == nil)
            #expect(userLocation["timezone"] == nil)
        } else {
            Issue.record("user_location not found")
        }
    }

    @Test("should handle web search with minimal user location (country only)")
    func handlesWebSearchWithMinimalUserLocation() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Here are global events."}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "What is the latest news?"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.web_search_20250305",
                    name: "web_search",
                    args: [
                        "maxUses": .number(1),
                        "userLocation": .object([
                            "type": .string("approximate"),
                            "country": .string("US")
                        ])
                    ]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        guard let tools = json?["tools"] as? [[String: Any]], tools.count == 1 else {
            Issue.record("Expected 1 tool in request")
            return
        }

        let tool = tools[0]
        #expect(tool["type"] as? String == "web_search_20250305")
        #expect(tool["name"] as? String == "web_search")
        #expect(tool["max_uses"] as? Int == 1)

        if let userLocation = tool["user_location"] as? [String: Any] {
            #expect(userLocation["type"] as? String == "approximate")
            #expect(userLocation["country"] as? String == "US")
            // city, region, timezone should not be present
            #expect(userLocation["city"] == nil)
            #expect(userLocation["region"] == nil)
            #expect(userLocation["timezone"] == nil)
        } else {
            Issue.record("user_location not found")
        }
    }
}

// MARK: - Batch 14: Web Fetch Tool Tests

@Suite("AnthropicMessagesLanguageModel web fetch")
struct AnthropicMessagesLanguageModelWebFetchTests {

    @Test("should send request body with web fetch tool")
    func sendsWebFetchRequestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Content fetched successfully."}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.web_fetch_20250910",
                    name: "web_fetch",
                    args: ["maxUses": .number(1)]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "claude-3-haiku-20240307")
        #expect(json?["max_tokens"] as? Int == 4096)

        guard let tools = json?["tools"] as? [[String: Any]], tools.count == 1 else {
            Issue.record("Expected 1 tool in request")
            return
        }

        let tool = tools[0]
        #expect(tool["type"] as? String == "web_fetch_20250910")
        #expect(tool["name"] as? String == "web_fetch")
        #expect(tool["max_uses"] as? Int == 1)
    }
}

// MARK: - Batch 14: Code Execution Tool Tests

@Suite("AnthropicMessagesLanguageModel code execution")
struct AnthropicMessagesLanguageModelCodeExecutionTests {

    @Test("should enable server-side code execution when using anthropic.tools.codeExecution_20250522")
    func enablesServerSideCodeExecution() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Here is a Python function to calculate factorial"}],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.code_execution_20250522",
                    name: "code_execution",
                    args: [:]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        guard let tools = json?["tools"] as? [[String: Any]], tools.count == 1 else {
            Issue.record("Expected 1 tool in request")
            return
        }

        let tool = tools[0]
        #expect(tool["type"] as? String == "code_execution_20250522")
        #expect(tool["name"] as? String == "code_execution")
        // Should not have any additional fields
        #expect(tool.count == 2)

        // Verify beta header is set
        if let headers = request.allHTTPHeaderFields {
            #expect(headers["anthropic-beta"] == "code-execution-2025-05-22")
        } else {
            Issue.record("No headers found")
        }
    }

    @Test("should handle server-side code execution results")
    func handlesServerSideCodeExecutionResults() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [
                {
                    "type": "server_tool_use",
                    "id": "tool_1",
                    "name": "code_execution",
                    "input": {"code": "print(\\"Hello, World!\\")"}
                },
                {
                    "type": "code_execution_tool_result",
                    "tool_use_id": "tool_1",
                    "content": {
                        "type": "code_execution_result",
                        "stdout": "Hello, World!\\n",
                        "stderr": "",
                        "return_code": 0
                    }
                },
                {
                    "type": "text",
                    "text": "The code executed successfully with output: Hello, World!"
                }
            ],
            "model": "claude-3-haiku-20240307",
            "stop_reason": "end_turn",
            "usage": {
                "input_tokens": 15,
                "output_tokens": 25,
                "server_tool_use": {"code_execution_requests": 1}
            }
        }
        """

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { ["x-api-key": "test-api-key", "anthropic-version": "2023-06-01"] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.code_execution_20250522",
                    name: "code_execution",
                    args: [:]
                ))
            ]
        ))

        // Verify content structure
        #expect(result.content.count == 3)

        // Verify tool call with providerExecuted=true
        if case .toolCall(let toolCall) = result.content[0] {
            #expect(toolCall.toolCallId == "tool_1")
            #expect(toolCall.toolName == "code_execution")
            // Input should be stringified JSON: {"code":"print(\"Hello, World!\")"}
            #expect(toolCall.input.contains("code"))
            #expect(toolCall.input.contains("Hello, World!"))
            #expect(toolCall.providerExecuted == true)
        } else {
            Issue.record("Expected tool-call at index 0")
        }

        // Verify tool result with providerExecuted=true
        if case .toolResult(let toolResult) = result.content[1] {
            #expect(toolResult.toolCallId == "tool_1")
            #expect(toolResult.toolName == "code_execution")
            #expect(toolResult.providerExecuted == true)

            // Verify result is JSONValue with code execution result
            if case .object(let resultObj) = toolResult.result {
                #expect(resultObj["type"] == .string("code_execution_result"))
                #expect(resultObj["stdout"] == .string("Hello, World!\n"))
                #expect(resultObj["stderr"] == .string(""))
                #expect(resultObj["return_code"] == .number(0))
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected tool-result at index 1")
        }

        // Verify text content
        if case .text(let textContent) = result.content[2] {
            #expect(textContent.text == "The code executed successfully with output: Hello, World!")
        } else {
            Issue.record("Expected text at index 2")
        }
    }
}

// MARK: - Batch 16: Provider Tool Results with Citations and Errors

@Suite("AnthropicMessagesLanguageModel provider tool results Batch 16")
struct AnthropicMessagesLanguageModelProviderToolResultsBatch16Tests {

    private func makeConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
        AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-api-key",
                "anthropic-version": "2023-06-01"
            ] },
            fetch: fetch
        )
    }

    @Test("should handle server-side web search results with citations")
    func handlesServerSideWebSearchResultsWithCitations() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [
                {
                    "type": "server_tool_use",
                    "id": "tool_1",
                    "name": "web_search",
                    "input": {"query": "latest AI news"}
                },
                {
                    "type": "web_search_tool_result",
                    "tool_use_id": "tool_1",
                    "content": [
                        {
                            "type": "web_search_result",
                            "url": "https://example.com/ai-news",
                            "title": "Latest AI Developments",
                            "encrypted_content": "encrypted_content_123",
                            "page_age": "January 15, 2025"
                        }
                    ]
                },
                {
                    "type": "text",
                    "text": "Based on recent articles, AI continues to advance rapidly."
                }
            ],
            "stop_reason": "end_turn",
            "usage": {
                "input_tokens": 10,
                "output_tokens": 20,
                "server_tool_use": {"web_search_requests": 1}
            }
        }
        """

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-5-sonnet-latest"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "What is the latest news?"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "anthropic.web_search_20250305",
                name: "web_search",
                args: ["maxUses": .number(5)]
            ))]
        ))

        // Verify tool call
        if case .toolCall(let toolCall) = result.content[0] {
            #expect(toolCall.toolCallId == "tool_1")
            #expect(toolCall.toolName == "web_search")
            #expect(toolCall.providerExecuted == true)

            let inputStr = toolCall.input as! String
            #expect(inputStr.contains("\"query\":\"latest AI news\""))
        } else {
            Issue.record("Expected tool-call at index 0")
        }

        // Verify tool result with array (index 1)
        if case .toolResult(let toolResult) = result.content[1] {
            #expect(toolResult.toolCallId == "tool_1")
            #expect(toolResult.toolName == "web_search")
            #expect(toolResult.providerExecuted == true)

            // Verify result is an array of web search results
            if case .array(let resultsArray) = toolResult.result {
                #expect(resultsArray.count == 1)

                if case .object(let searchResult) = resultsArray[0] {
                    #expect(searchResult["type"] == .string("web_search_result"))
                    #expect(searchResult["url"] == .string("https://example.com/ai-news"))
                    #expect(searchResult["title"] == .string("Latest AI Developments"))
                    #expect(searchResult["encryptedContent"] == .string("encrypted_content_123"))
                    #expect(searchResult["pageAge"] == .string("January 15, 2025"))
                } else {
                    Issue.record("Expected object in results array")
                }
            } else {
                Issue.record("Expected array result")
            }
        } else {
            Issue.record("Expected tool-result at index 1")
        }

        // Verify source citation content (index 2)
        if case .source(let source) = result.content[2] {
            if case .url(let id, let url, let title, let providerMetadata) = source {
                #expect(url == "https://example.com/ai-news")
                #expect(title == "Latest AI Developments")

                // Verify provider metadata
                if let anthropicMeta = providerMetadata?["anthropic"] {
                    #expect(anthropicMeta["pageAge"] == JSONValue.string("January 15, 2025"))
                } else {
                    Issue.record("Expected anthropic provider metadata")
                }
            } else {
                Issue.record("Expected url source")
            }
        } else {
            Issue.record("Expected source at index 2")
        }

        // Verify text content
        if case .text(let textContent) = result.content[3] {
            #expect(textContent.text == "Based on recent articles, AI continues to advance rapidly.")
        } else {
            Issue.record("Expected text at index 3")
        }
    }

    @Test("should handle server-side web search errors")
    func handlesServerSideWebSearchErrors() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [
                {
                    "type": "web_search_tool_result",
                    "tool_use_id": "tool_1",
                    "content": {
                        "type": "web_search_tool_result_error",
                        "error_code": "max_uses_exceeded"
                    }
                },
                {
                    "type": "text",
                    "text": "I cannot search further due to limits."
                }
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-5-sonnet-latest"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "What is the latest news?"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "anthropic.web_search_20250305",
                name: "web_search",
                args: ["maxUses": .number(1)]
            ))]
        ))

        // Verify error tool result
        if case .toolResult(let toolResult) = result.content[0] {
            #expect(toolResult.toolCallId == "tool_1")
            #expect(toolResult.toolName == "web_search")
            #expect(toolResult.providerExecuted == true)
            #expect(toolResult.isError == true)

            // Verify error object
            if case .object(let errorObj) = toolResult.result {
                #expect(errorObj["type"] == .string("web_search_tool_result_error"))
                #expect(errorObj["errorCode"] == .string("max_uses_exceeded"))
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected tool-result at index 0")
        }

        // Verify text content
        if case .text(let textContent) = result.content[1] {
            #expect(textContent.text == "I cannot search further due to limits.")
        } else {
            Issue.record("Expected text at index 1")
        }
    }

    @Test("should handle web fetch tool results with title")
    func handlesWebFetchWithTitle() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [
                {
                    "type": "text",
                    "text": "I'll fetch the Wikipedia page."
                },
                {
                    "type": "server_tool_use",
                    "id": "tool_1",
                    "name": "web_fetch",
                    "input": {"url": "https://en.wikipedia.org/wiki/Test"}
                },
                {
                    "type": "web_fetch_tool_result",
                    "tool_use_id": "tool_1",
                    "content": {
                        "type": "web_fetch_result",
                        "url": "https://en.wikipedia.org/wiki/Test",
                        "retrieved_at": "2025-07-17T21:38:38.606000+00:00",
                        "content": {
                            "type": "document",
                            "source": {
                                "type": "text",
                                "media_type": "text/plain",
                                "data": "Test article content here."
                            },
                            "title": "Test Article"
                        }
                    }
                }
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20, "server_tool_use": {"web_fetch_requests": 1}}
        }
        """

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-5-sonnet-latest"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Fetch the page"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "anthropic.web_fetch_20250910",
                name: "web_fetch",
                args: ["maxUses": .number(1)]
            ))]
        ))

        // Verify tool call
        if case .toolCall(let toolCall) = result.content[1] {
            #expect(toolCall.toolCallId == "tool_1")
            #expect(toolCall.toolName == "web_fetch")
            #expect(toolCall.providerExecuted == true)
        } else {
            Issue.record("Expected tool-call at index 1")
        }

        // Verify tool result
        if case .toolResult(let toolResult) = result.content[2] {
            #expect(toolResult.toolCallId == "tool_1")
            #expect(toolResult.toolName == "web_fetch")
            #expect(toolResult.providerExecuted == true)

            // Verify web_fetch_result structure
            if case .object(let resultObj) = toolResult.result {
                #expect(resultObj["type"] == .string("web_fetch_result"))
                #expect(resultObj["url"] == .string("https://en.wikipedia.org/wiki/Test"))
                #expect(resultObj["retrievedAt"] == .string("2025-07-17T21:38:38.606000+00:00"))

                // Verify content
                if case .object(let content) = resultObj["content"] {
                    #expect(content["type"] == .string("document"))
                    #expect(content["title"] == .string("Test Article"))

                    // Verify source
                    if case .object(let source) = content["source"] {
                        #expect(source["type"] == .string("text"))
                        #expect(source["mediaType"] == .string("text/plain"))
                        #expect(source["data"] == .string("Test article content here."))
                    } else {
                        Issue.record("Expected source object")
                    }
                } else {
                    Issue.record("Expected content object")
                }
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected tool-result at index 2")
        }
    }

    @Test("should handle web fetch tool results without title")
    func handlesWebFetchWithoutTitle() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [
                {
                    "type": "server_tool_use",
                    "id": "tool_1",
                    "name": "web_fetch",
                    "input": {"url": "https://example.com/file.pdf"}
                },
                {
                    "type": "web_fetch_tool_result",
                    "tool_use_id": "tool_1",
                    "content": {
                        "type": "web_fetch_result",
                        "url": "https://example.com/file.pdf",
                        "retrieved_at": "2025-09-29T07:28:57.560000+00:00",
                        "content": {
                            "type": "document",
                            "source": {
                                "type": "text",
                                "media_type": "text/plain",
                                "data": "PDF content here"
                            },
                            "title": null
                        }
                    }
                }
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-5-sonnet-latest"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Fetch the PDF"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "anthropic.web_fetch_20250910",
                name: "web_fetch",
                args: [:]
            ))]
        ))

        // Verify tool result without title
        if case .toolResult(let toolResult) = result.content[1] {
            if case .object(let resultObj) = toolResult.result {
                if case .object(let content) = resultObj["content"] {
                    // title should be null
                    #expect(content["title"] == .null)
                } else {
                    Issue.record("Expected content object")
                }
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected tool-result at index 1")
        }
    }

    @Test("should handle web fetch unavailable errors")
    func handlesWebFetchUnavailableErrors() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [
                {
                    "type": "server_tool_use",
                    "id": "tool_1",
                    "name": "web_fetch",
                    "input": {"url": "https://example.com/unavailable"}
                },
                {
                    "type": "web_fetch_tool_result",
                    "tool_use_id": "tool_1",
                    "content": {
                        "type": "web_fetch_tool_result_error",
                        "error_code": "unavailable"
                    }
                },
                {
                    "type": "text",
                    "text": "The fetch service is unavailable."
                }
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-5-sonnet-latest"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Fetch page"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "anthropic.web_fetch_20250910",
                name: "web_fetch",
                args: [:]
            ))]
        ))

        // Verify error tool result
        if case .toolResult(let toolResult) = result.content[1] {
            #expect(toolResult.toolCallId == "tool_1")
            #expect(toolResult.toolName == "web_fetch")
            #expect(toolResult.providerExecuted == true)
            #expect(toolResult.isError == true)

            // Verify error object
            if case .object(let errorObj) = toolResult.result {
                #expect(errorObj["type"] == .string("web_fetch_tool_result_error"))
                #expect(errorObj["errorCode"] == .string("unavailable"))
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected tool-result at index 1")
        }
    }

    @Test("should handle code execution errors")
    func handlesCodeExecutionErrors() async throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [
                {
                    "type": "code_execution_tool_result",
                    "tool_use_id": "tool_1",
                    "content": {
                        "type": "code_execution_tool_result_error",
                        "error_code": "unavailable"
                    }
                },
                {
                    "type": "text",
                    "text": "The code execution service is currently unavailable."
                }
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-5-sonnet-latest"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Run code"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "anthropic.code_execution_20250522",
                name: "code_execution",
                args: [:]
            ))]
        ))

        // Verify error tool result
        if case .toolResult(let toolResult) = result.content[0] {
            #expect(toolResult.toolCallId == "tool_1")
            #expect(toolResult.toolName == "code_execution")
            #expect(toolResult.providerExecuted == true)
            #expect(toolResult.isError == true)

            // Verify error object
            if case .object(let errorObj) = toolResult.result {
                #expect(errorObj["type"] == .string("code_execution_tool_result_error"))
                #expect(errorObj["errorCode"] == .string("unavailable"))
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected tool-result at index 0")
        }

        // Verify text content
        if case .text(let textContent) = result.content[1] {
            #expect(textContent.text == "The code execution service is currently unavailable.")
        } else {
            Issue.record("Expected text at index 1")
        }
    }
}

// MARK: - Batch 17: Streaming Request Body + Client-side Tools Mix

@Suite("AnthropicMessagesLanguageModel Batch 17")
struct AnthropicMessagesLanguageModelBatch17Tests {

    actor RequestCapture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func get() -> URLRequest? { request }
    }

    private func makeConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
        AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-api-key",
                "anthropic-version": "2023-06-01"
            ] },
            fetch: fetch
        )
    }

    private func makeStream(events: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data((event + "\n\n").utf8))
            }
            continuation.finish()
        }
    }

    @Test("doStream should pass the messages and the model")
    func doStreamPassesMessagesAndModel() async throws {
        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["test-header": "test-value"])!

        let events = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["stream"] as? Bool == true)
        #expect(json?["model"] as? String == "claude-3-haiku-20240307")
        #expect(json?["max_tokens"] as? Int == 4096)

        let messages = json?["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?[0]["role"] as? String == "user")

        let content = messages?[0]["content"] as? [[String: Any]]
        #expect(content?.count == 1)
        #expect(content?[0]["type"] as? String == "text")
        #expect(content?[0]["text"] as? String == "Hello")
    }

    @Test("doStream should pass headers")
    func doStreamPassesHeaders() async throws {
        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: ["test-header": "test-value"])!

        let events = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let config = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-api-key",
                "anthropic-version": "2023-06-01",
                "Custom-Provider-Header": "provider-header-value"
            ] },
            fetch: fetch
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: config
        )

        _ = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.get() else {
            Issue.record("No request captured")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        #expect(headers["x-api-key"] == "test-api-key")
        #expect(headers["anthropic-version"] == "2023-06-01")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
    }

    @Test("doStream should send request body")
    func doStreamSendsRequestBody() async throws {
        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let events = [
            #"data: {"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}"#,
            #"data: {"type":"message_stop"}"#
        ]

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(events: events)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        // Verify request body structure
        guard let request = await capture.get(), let bodyData = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(json?["model"] as? String == "claude-3-haiku-20240307")
        #expect(json?["max_tokens"] as? Int == 4096)
        #expect(json?["stream"] as? Bool == true)

        let messages = json?["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)

        let message = messages?[0]
        #expect(message?["role"] as? String == "user")

        let content = message?["content"] as? [[String: Any]]
        #expect(content?.count == 1)
        #expect(content?[0]["type"] as? String == "text")
        #expect(content?[0]["text"] as? String == "Hello")
    }

    @Test("web search should work alongside regular client-side tools")
    func webSearchWorksWithClientSideTools() async throws {
        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [{"type": "text", "text": "I can search and calculate."}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "calculator",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    description: "Calculate math",
                    providerOptions: nil
                )),
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.web_search_20250305",
                    name: "web_search",
                    args: ["maxUses": .number(1)]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let tools = json?["tools"] as? [[String: Any]]
        #expect(tools?.count == 2)

        // Verify function tool
        #expect(tools?[0]["name"] as? String == "calculator")
        #expect(tools?[0]["description"] as? String == "Calculate math")
        let inputSchema = tools?[0]["input_schema"] as? [String: Any]
        #expect(inputSchema?["type"] as? String == "object")

        // Verify provider-defined tool
        #expect(tools?[1]["type"] as? String == "web_search_20250305")
        #expect(tools?[1]["name"] as? String == "web_search")
        #expect(tools?[1]["max_uses"] as? Int == 1)
    }

    @Test("code execution should work alongside regular client-side tools")
    func codeExecutionWorksWithClientSideTools() async throws {
        let capture = RequestCapture()
        let httpResponse = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)!

        let responseBody = """
        {
            "type": "message",
            "id": "msg_test",
            "content": [{"type": "text", "text": "I can execute code and calculate."}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 20}
        }
        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data(responseBody.utf8)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "calculator",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    description: "Calculate math expressions",
                    providerOptions: nil
                )),
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "anthropic.code_execution_20250522",
                    name: "code_execution",
                    args: [:]
                ))
            ]
        ))

        guard let request = await capture.get(), let body = request.httpBody else {
            Issue.record("No request captured")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let tools = json?["tools"] as? [[String: Any]]
        #expect(tools?.count == 2)

        // Verify function tool (should NOT have type field)
        #expect(tools?[0]["name"] as? String == "calculator")
        #expect(tools?[0]["description"] as? String == "Calculate math expressions")
        #expect(tools?[0]["type"] == nil)

        // Verify provider-defined tool
        #expect(tools?[1]["type"] as? String == "code_execution_20250522")
        #expect(tools?[1]["name"] as? String == "code_execution")

        // Verify beta header
        let headers = request.allHTTPHeaderFields ?? [:]
        #expect(headers["anthropic-beta"] == "code-execution-2025-05-22")
    }
}
