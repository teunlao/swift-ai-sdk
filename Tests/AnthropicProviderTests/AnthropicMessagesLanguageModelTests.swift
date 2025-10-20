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
