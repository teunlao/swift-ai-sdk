import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let samplePrompt: LanguageModelV3Prompt = [
    .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
]

private final class SequentialIdGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var counter: Int = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let value = counter
        counter += 1
        return "generated-\(value)"
    }
}

@Suite("OpenAIResponsesLanguageModel")
struct OpenAIResponsesLanguageModelTests {
    private func makeConfig(fetch: @escaping FetchFunction, fileIdPrefixes: [String]? = ["file-"]) -> OpenAIConfig {
        let generator = SequentialIdGenerator()
        return OpenAIConfig(
            provider: "openai.responses",
            url: { options in "https://api.openai.com/v1\(options.path)" },
            headers: { [:] },
            fetch: fetch,
            generateId: { generator.next() },
            fileIdPrefixes: fileIdPrefixes
        )
    }

    private func decodeRequestBody(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test("doGenerate maps response content, metadata, and warnings")
    func testDoGenerateMapsResponse() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o-2024-07-18",
            "output": [
                [
                    "id": "msg_1",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Answer text",
                            "annotations": [],
                            "logprobs": [
                                [
                                    "token": "Answer",
                                    "logprob": -0.1,
                                    "bytes": [65, 110, 115, 119, 101, 114],
                                    "top_logprobs": []
                                ]
                            ]
                        ]
                    ]
                ],
                [
                    "id": "tool_item",
                    "type": "function_call",
                    "status": "completed",
                    "name": "lookup_city",
                    "call_id": "tool-1",
                    "arguments": "{\"city\":\"Berlin\"}"
                ],
                [
                    "id": "reasoning_1",
                    "type": "reasoning",
                    "summary": [
                        ["type": "summary_text", "text": "Step 1"]
                    ],
                    "encrypted_content": "encrypted-block"
                ]
            ],
            "service_tier": "default",
            "usage": [
                "input_tokens": 12,
                "input_tokens_details": ["cached_tokens": 3],
                "output_tokens": 7,
                "output_tokens_details": ["reasoning_tokens": 2]
            ],
            "warnings": [
                [
                    "type": "unsupported-setting",
                    "setting": "topK",
                    "message": "topK is not supported"
                ]
            ],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-2024-07-18",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "lookup_city",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "city": .object(["type": .string("string")])
                ]),
                "required": .array([.string("city")])
            ]),
            description: "Lookup a city"
        ))

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        #expect(result.content.contains { content in
            if case .text(let text) = content {
                return text.text == "Answer text"
            }
            return false
        })

        #expect(result.content.contains { content in
            if case .reasoning(let reasoning) = content {
                return reasoning.text == "Step 1"
            }
            return false
        })

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        #expect(toolCalls.count == 1)
        #expect(toolCalls.first?.toolCallId == "tool-1")
        #expect(toolCalls.first?.toolName == "lookup_city")
        #expect(toolCalls.first?.input == "{\"city\":\"Berlin\"}")

        #expect(result.finishReason == .toolCalls)
        #expect(result.usage.inputTokens == 12)
        #expect(result.usage.outputTokens == 7)
        #expect(result.usage.totalTokens == 19)
        #expect(result.usage.reasoningTokens == 2)
        #expect(result.usage.cachedInputTokens == 3)

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata["responseId"] == .string("resp_123"))
            #expect(metadata["serviceTier"] == .string("default"))
        } else {
            Issue.record("Missing provider metadata")
        }

        #expect(result.warnings.count == 1)
        if result.warnings.count == 1 {
            switch result.warnings[0] {
            case .unsupportedSetting(let setting, _):
                #expect(setting == "topK")
            default:
                Issue.record("Unexpected warning type")
            }
        }

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request for verification")
            return
        }

        #expect(json["model"] as? String == "gpt-4o-2024-07-18")
        #expect(json["stream"] == nil)

        if let tools = json["tools"] as? [[String: Any]] {
            #expect(tools.count == 1)
            #expect(tools.first?["type"] as? String == "function")
        } else {
            Issue.record("Expected tools array in request")
        }
    }

    @Test("doGenerate maps mcp_call to toolCall and toolResult")
    func testDoGenerateMapsMcpCall() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_mcp",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o-2024-07-18",
            "output": [
                [
                    "id": "mcp_item_1",
                    "type": "mcp_call",
                    "name": "list_files",
                    "arguments": "{\"path\":\"/\"}",
                    "server_label": "My MCP",
                    "output": "ok",
                    "error": NSNull()
                ]
            ],
            "service_tier": "default",
            "usage": [
                "input_tokens": 1,
                "output_tokens": 1
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-2024-07-18",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: samplePrompt)
        )

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let result) = content { return result }
            return nil
        }

        guard let toolCall = toolCalls.first else {
            Issue.record("Expected tool-call for mcp_call")
            return
        }
        #expect(toolCall.toolCallId == "mcp_item_1")
        #expect(toolCall.toolName == "mcp.list_files")
        #expect(toolCall.providerExecuted == true)
        #expect(toolCall.dynamic == true)

        guard let toolResult = toolResults.first else {
            Issue.record("Expected tool-result for mcp_call")
            return
        }
        #expect(toolResult.toolCallId == "mcp_item_1")
        #expect(toolResult.toolName == "mcp.list_files")
        #expect(toolResult.providerExecuted == true)

        if let openaiMetadata = toolResult.providerMetadata?["openai"] {
            #expect(openaiMetadata["itemId"] == .string("mcp_item_1"))
        } else {
            Issue.record("Missing provider metadata for mcp_call result")
        }

        guard case .object(let resultObject) = toolResult.result else {
            Issue.record("Expected object result for mcp_call")
            return
        }
        #expect(resultObject["type"] == .string("call"))
        #expect(resultObject["serverLabel"] == .string("My MCP"))
        #expect(resultObject["name"] == .string("list_files"))
        #expect(resultObject["arguments"] == .string("{\"path\":\"/\"}"))
        #expect(resultObject["output"] == .string("ok"))
    }

    @Test("doGenerate does not send truncation by default")
    func testDoGenerateDoesNotSendTruncationByDefault() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_trunc_default",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o-2024-07-18",
            "output": [],
            "service_tier": NSNull(),
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-2024-07-18",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let body = decodeRequestBody(request.httpBody)
        #expect(body?["truncation"] == nil)
    }

    @Test("doGenerate sends truncation when specified in provider options")
    func testDoGenerateSendsTruncationWhenSpecified() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_trunc_auto",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o-2024-07-18",
            "output": [],
            "service_tier": NSNull(),
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-2024-07-18",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: samplePrompt,
            providerOptions: [
                "openai": [
                    "truncation": .string("auto")
                ]
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let body = decodeRequestBody(request.httpBody)
        #expect(body?["truncation"] as? String == "auto")
    }

    @Test("doGenerate maps unknown finish reason to other")
    func testDoGenerateUnknownFinishReasonMapsToOther() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_incomplete_other",
            "created_at": 1_742_250_000.0,
            "model": "gpt-4o",
            "output": [],
            "service_tier": NSNull(),
            "usage": ["input_tokens": 2, "output_tokens": 2, "total_tokens": 4],
            "warnings": [],
            "incomplete_details": ["reason": "some_new_reason"],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))
        #expect(result.finishReason == .other)
    }

    @Test("doGenerate maps mcp_approval_request to toolCall and tool-approval-request")
    func testDoGenerateMapsMcpApprovalRequest() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_mcp_approval",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o-2024-07-18",
            "output": [
                [
                    "id": "mcp_req_item_1",
                    "type": "mcp_approval_request",
                    "name": "list_files",
                    "arguments": "{\"path\":\"/\"}",
                    "approval_request_id": "approval_1"
                ]
            ],
            "service_tier": "default",
            "usage": [
                "input_tokens": 1,
                "output_tokens": 1
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-2024-07-18",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: samplePrompt)
        )

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let approvalRequests = result.content.compactMap { content -> LanguageModelV3ToolApprovalRequest? in
            if case .toolApprovalRequest(let request) = content { return request }
            return nil
        }

        guard let toolCall = toolCalls.first else {
            Issue.record("Expected tool-call for mcp_approval_request")
            return
        }
        #expect(toolCall.toolCallId == "generated-0")
        #expect(toolCall.toolName == "mcp.list_files")
        #expect(toolCall.providerExecuted == true)
        #expect(toolCall.dynamic == true)
        if let openaiMetadata = toolCall.providerMetadata?["openai"] {
            #expect(openaiMetadata["approvalRequestId"] == .string("approval_1"))
        } else {
            Issue.record("Missing provider metadata for mcp_approval_request tool call")
        }

        guard let approvalRequest = approvalRequests.first else {
            Issue.record("Expected tool-approval-request for mcp_approval_request")
            return
        }
        #expect(approvalRequest.approvalId == "approval_1")
        #expect(approvalRequest.toolCallId == "generated-0")
    }

    @Test("doGenerate aliases mcp_call toolCallId using approvalRequestId from prompt")
    func testDoGenerateAliasesMcpCallUsingPromptMapping() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "dummy-tool-call",
                        toolName: "mcp.list_files",
                        input: .object([:]),
                        providerExecuted: true,
                        providerOptions: [
                            "openai": ["approvalRequestId": .string("approval_1")]
                        ]
                    ))
                ],
                providerOptions: nil
            ),
            .user(content: [.text(LanguageModelV3TextPart(text: "Continue"))], providerOptions: nil)
        ]

        let responseJSON: [String: Any] = [
            "id": "resp_mcp_call_after_approval",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o-2024-07-18",
            "output": [
                [
                    "id": "mcp_item_2",
                    "type": "mcp_call",
                    "name": "list_files",
                    "arguments": "{\"path\":\"/\"}",
                    "server_label": "My MCP",
                    "approval_request_id": "approval_1",
                    "output": "ok",
                    "error": NSNull()
                ]
            ],
            "service_tier": "default",
            "usage": [
                "input_tokens": 1,
                "output_tokens": 1
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-2024-07-18",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: prompt)
        )

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let result) = content { return result }
            return nil
        }

        guard let toolCall = toolCalls.first, let toolResult = toolResults.first else {
            Issue.record("Expected tool-call and tool-result for aliased mcp_call")
            return
        }

        #expect(toolCall.toolCallId == "dummy-tool-call")
        #expect(toolResult.toolCallId == "dummy-tool-call")
        if let openaiMetadata = toolResult.providerMetadata?["openai"] {
            #expect(openaiMetadata["itemId"] == .string("mcp_item_2"))
        } else {
            Issue.record("Missing provider metadata for aliased mcp_call result")
        }
    }

    @Test("doStream emits text deltas and finish metadata")
    func testDoStreamEmitsTextDeltas() async throws {
        actor RequestCapture {
            var bodyData: Data?
            func store(_ data: Data?) { bodyData = data }
            func current() -> Data? { bodyData }
        }

        let capture = RequestCapture()

        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            guard let string = String(data: data, encoding: .utf8) else {
                fatalError("Unable to encode chunk value")
            }
            return "data:\(string)\n\n"
        }

        let chunkStrings: [String] = [
            chunk([
                "type": "response.created",
                "response": [
                    "id": "resp_stream",
                    "object": "response",
                    "created_at": 1_741_269_019.0,
                    "status": "in_progress",
                    "error": NSNull(),
                    "incomplete_details": NSNull(),
                    "model": "gpt-4o-2024-07-18",
                    "service_tier": "default"
                ]
            ]),
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "msg_stream",
                    "type": "message",
                    "status": "in_progress",
                    "role": "assistant",
                    "content": []
                ]
            ]),
            chunk([
                "type": "response.content_part.added",
                "item_id": "msg_stream",
                "output_index": 0,
                "content_index": 0,
                "part": [
                    "type": "output_text",
                    "text": "",
                    "annotations": [],
                    "logprobs": []
                ]
            ]),
            chunk([
                "type": "response.output_text.delta",
                "item_id": "msg_stream",
                "output_index": 0,
                "content_index": 0,
                "delta": "Hello",
                "logprobs": [
                    [
                        "token": "Hello",
                        "logprob": -0.1,
                        "bytes": [72, 101, 108, 108, 111],
                        "top_logprobs": []
                    ]
                ]
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "msg_stream",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Hello",
                            "annotations": [],
                            "logprobs": []
                        ]
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_stream",
                    "object": "response",
                    "created_at": 1_741_269_019.0,
                    "status": "completed",
                    "error": NSNull(),
                    "incomplete_details": NSNull(),
                    "model": "gpt-4o-2024-07-18",
                    "service_tier": "default",
                    "usage": [
                        "input_tokens": 543,
                        "input_tokens_details": ["cached_tokens": 234],
                        "output_tokens": 478,
                        "output_tokens_details": ["reasoning_tokens": 123]
                    ],
                    "output": [
                        [
                            "id": "msg_stream",
                            "type": "message",
                            "status": "completed",
                            "role": "assistant",
                            "content": [
                                [
                                    "type": "output_text",
                                    "text": "Hello",
                                    "annotations": [],
                                    "logprobs": []
                                ]
                            ]
                        ]
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunkStrings {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-2024-07-18",
            config: makeConfig(fetch: fetch)
        )

        let options = LanguageModelV3CallOptions(
            prompt: samplePrompt,
            includeRawChunks: false,
            providerOptions: [
                "openai": [
                    "logprobs": .bool(true)
                ]
            ]
        )

        let streamResult = try await model.doStream(options: options)

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.count >= 5)

        if parts.count >= 1 {
            if case .streamStart(let warnings) = parts[0] {
                #expect(warnings.isEmpty)
            } else {
                Issue.record("Expected stream-start part")
            }
        }

        if parts.count >= 2 {
            if case .responseMetadata(let id, let modelId, let timestamp) = parts[1] {
                #expect(id == "resp_stream")
                #expect(modelId == "gpt-4o-2024-07-18")
                #expect(timestamp == Date(timeIntervalSince1970: 1_741_269_019))
            } else {
                Issue.record("Expected response-metadata part")
            }
        }

        if parts.count >= 3 {
            if case .textStart(let id, let metadata) = parts[2] {
                #expect(id == "msg_stream")
                if let openaiMetadata = metadata?["openai"] {
                    #expect(openaiMetadata["itemId"] == .string("msg_stream"))
                } else {
                    Issue.record("Missing provider metadata on text-start")
                }
            } else {
                Issue.record("Expected text-start part")
            }
        }

        if parts.count >= 4 {
            if case .textDelta(let id, let delta, _) = parts[3] {
                #expect(id == "msg_stream")
                #expect(delta == "Hello")
            } else {
                Issue.record("Expected text-delta part")
            }
        }

        if let finishPart = parts.last {
            if case .finish(let finishReason, let usage, let providerMetadata) = finishPart {
                #expect(finishReason == .stop)
                #expect(usage.inputTokens == 543)
                #expect(usage.outputTokens == 478)
                #expect(usage.cachedInputTokens == 234)
                #expect(usage.reasoningTokens == 123)
                if let openaiMetadata = providerMetadata?["openai"] {
                    #expect(openaiMetadata["responseId"] == .string("resp_stream"))
                    if let logprobs = openaiMetadata["logprobs"], case .array(let array) = logprobs {
                        #expect(!array.isEmpty)
                    } else {
                        Issue.record("Expected logprobs in provider metadata")
                    }
                } else {
                    Issue.record("Missing provider metadata on finish")
                }
            } else {
                Issue.record("Expected finish part at end of stream")
            }
        }

        if let data = await capture.current(),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            #expect(json["stream"] as? Bool == true)
            #expect(json["top_logprobs"] as? Int == TOP_LOGPROBS_MAX)
        } else {
            Issue.record("Missing captured request body")
        }
    }

    @Test("doGenerate warns for unsupported settings on reasoning model")
    func testDoGenerateReasoningModelUnsupportedSettings() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_reasoning",
            "created_at": 1_700_000_500.0,
            "model": "o3-mini",
            "output": [],
            "service_tier": "priority",
            "usage": [
                "input_tokens": 10,
                "output_tokens": 4,
                "total_tokens": 14,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens_details": ["reasoning_tokens": 2]
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [
                    .system(content: "Be safe", providerOptions: nil),
                    .user(content: [.text(LanguageModelV3TextPart(text: "Explain"))], providerOptions: nil)
                ],
                temperature: 0.5,
                topP: 0.2
            )
        )

        #expect(result.warnings.count == 2)
        if result.warnings.count == 2 {
            let settings = result.warnings.compactMap { warning -> String? in
                if case let .unsupportedSetting(setting, _) = warning { return setting }
                return nil
            }
            #expect(settings.contains("temperature"))
            #expect(settings.contains("topP"))
        }

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata["responseId"] == .string("resp_reasoning"))
            #expect(metadata["serviceTier"] == .string("priority"))
        }

        if let data = await capture.current(),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let input = json["input"] as? [[String: Any]],
           let first = input.first {
            #expect(first["role"] as? String == "developer")
        } else {
            Issue.record("Expected captured reasoning request body")
        }
    }

    @Test("doGenerate sends JSON response format metadata")
    func testDoGenerateSendsJSONFormat() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_json_format",
            "created_at": 1_700_100_000.0,
            "model": "gpt-4o",
            "output": [],
            "service_tier": "default",
            "usage": [
                "input_tokens": 5,
                "output_tokens": 3,
                "total_tokens": 8
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let schema: JSONValue = .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": .string("string")])
            ]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false)
        ])

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                responseFormat: .json(schema: schema, name: "response", description: "A response")
            )
        )

        if let data = await capture.current(),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? [String: Any],
           let format = text["format"] as? [String: Any] {
            #expect(format["name"] as? String == "response")
            #expect(format["description"] as? String == "A response")
            #expect(format["type"] as? String == "json_schema")
            #expect(format["strict"] as? Bool == true)
        } else {
            Issue.record("Missing JSON response format in request body")
        }
    }

    @Test("doStream emits tool call workflow with arguments and finish")
    func testDoStreamEmitsToolCallWorkflow() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            guard let string = String(data: data, encoding: .utf8) else {
                fatalError("Unable to encode chunk value")
            }
            return "data:\(string)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "call_item",
                    "type": "function_call",
                    "status": "in_progress",
                    "name": "lookup_weather",
                    "call_id": "tool-42"
                ]
            ]),
            chunk([
                "type": "response.function_call_arguments.delta",
                "output_index": 0,
                "delta": "{\"city\":",
                "sequence_number": 1
            ]),
            chunk([
                "type": "response.function_call_arguments.delta",
                "output_index": 0,
                "delta": "\"Berlin\"}",
                "sequence_number": 2
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "call_item",
                    "type": "function_call",
                    "status": "completed",
                    "name": "lookup_weather",
                    "call_id": "tool-42",
                    "arguments": "{\"city\":\"Berlin\"}"
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_tool",
                    "object": "response",
                    "created_at": 1_741_400_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 11,
                        "output_tokens": 5,
                        "total_tokens": 16
                    ],
                    "service_tier": "default"
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                includeRawChunks: false
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolInputStart(let id, let name, _, let executed, _, _) = part {
                return id == "tool-42" && name == "lookup_weather" && executed == nil
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolInputDelta(let id, let delta, _) = part {
                return id == "tool-42" && delta.contains("city")
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolInputEnd(let id, _) = part {
                return id == "tool-42"
            }
            return false
        })

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        #expect(toolCalls.contains { $0.toolCallId == "tool-42" && $0.toolName == "lookup_weather" })

        if let finish = parts.last {
            if case .finish(let reason, let usage, _) = finish {
                #expect(reason == .toolCalls)
                #expect(usage.totalTokens == 16)
            } else {
                Issue.record("Expected finish part for tool stream")
            }
        }

        if let data = await capture.current(),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            #expect(json["stream"] as? Bool == true)
        } else {
            Issue.record("Missing request body for tool stream")
        }
    }

    @Test("doGenerate formats json_object when schema missing")
    func testDoGenerateJsonObjectFormat() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_json_object",
            "created_at": 1_700_200_000.0,
            "model": "gpt-4o",
            "output": [],
            "service_tier": NSNull(),
            "usage": [
                "input_tokens": 1,
                "output_tokens": 1,
                "total_tokens": 2
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                responseFormat: .json(schema: nil, name: nil, description: nil)
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any],
              let format = text["format"] as? [String: Any] else {
            Issue.record("Missing json_object text format in request")
            return
        }

        #expect(format["type"] as? String == "json_object")
        #expect(format["strict"] == nil)
    }

    @Test("doGenerate forwards parallelToolCalls option")
    func testDoGenerateParallelToolCallsOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let minimalResponse: [String: Any] = [
            "id": "resp_parallel",
            "created_at": 1_700_300_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: minimalResponse)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "parallelToolCalls": .bool(false)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body for parallelToolCalls")
            return
        }

        #expect(json["parallel_tool_calls"] as? Bool == false)
    }

    @Test("doGenerate store=false adds reasoning include for reasoning models")
    func testDoGenerateStoreFalseReasoningModel() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let minimalResponse: [String: Any] = [
            "id": "resp_store_reasoning",
            "created_at": 1_700_400_000.0,
            "model": "gpt-5-mini",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: minimalResponse)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5-mini",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "store": .bool(false)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let include = json["include"] as? [String] else {
            Issue.record("Missing include array for reasoning store=false")
            return
        }

        #expect(Set(include) == Set(["reasoning.encrypted_content"]))
        #expect(json["store"] as? Bool == false)
    }

    @Test("doGenerate store=false leaves include empty for non-reasoning model")
    func testDoGenerateStoreFalseNonReasoningModel() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let minimalResponse: [String: Any] = [
            "id": "resp_store_standard",
            "created_at": 1_700_500_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: minimalResponse)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "store": .bool(false)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body for store=false non reasoning")
            return
        }

        #expect(json["include"] == nil)
        #expect(json["store"] as? Bool == false)
    }

    @Test("doGenerate warns about reasoningEffort for non-reasoning models")
    func testDoGenerateReasoningEffortWarning() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_reasoning_effort",
            "created_at": 1_700_600_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "reasoningEffort": .string("low")
                    ]
                ]
            )
        )

        #expect(result.warnings.contains { warning in
            if case let .unsupportedSetting(setting, _) = warning {
                return setting == "reasoningEffort"
            }
            return false
        })
    }

    @Test("doGenerate forwards instructions and include options")
    func testDoGenerateInstructionsAndInclude() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_instructions",
            "created_at": 1_700_700_000.0,
            "model": "o3-mini",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "instructions": .string("Be concise"),
                        "include": .array([
                            .string("reasoning.encrypted_content"),
                            .string("file_search_call.results")
                        ])
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body for instructions test")
            return
        }

        #expect(json["instructions"] as? String == "Be concise")
        if let include = json["include"] as? [String] {
            #expect(Set(include) == Set(["reasoning.encrypted_content", "file_search_call.results"]))
        } else {
            Issue.record("Missing include array in request")
        }
    }

    @Test("doGenerate forwards textVerbosity option")
    func testDoGenerateTextVerbosity() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_text_verbosity",
            "created_at": 1_700_800_000.0,
            "model": "gpt-5",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "textVerbosity": .string("low")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any] else {
            Issue.record("Missing text payload for verbosity")
            return
        }

        #expect(text["verbosity"] as? String == "low")
    }

    @Test("doGenerate include logprobs requests top_logprobs")
    func testDoGenerateLogprobsRequests() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_logprobs",
            "created_at": 1_700_900_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "logprobs": .bool(true)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body for logprobs")
            return
        }

        if let include = json["include"] as? [String] {
            #expect(include.contains("message.output_text.logprobs"))
        } else {
            Issue.record("Missing include array for logprobs")
        }
        #expect(json["top_logprobs"] as? Int == TOP_LOGPROBS_MAX)
    }

    @Test("doGenerate auto-includes provider tool sources and outputs")
    func testDoGenerateAutoIncludesProviderTools() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let minimalResponse: [String: Any] = [
            "id": "resp_tools",
            "created_at": 1_701_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: minimalResponse)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let webSearchTool = LanguageModelV3Tool.providerDefined(.init(id: "openai.web_search", name: "web_search", args: [:]))
        let codeInterpreterTool = LanguageModelV3Tool.providerDefined(.init(id: "openai.code_interpreter", name: "code_interpreter", args: [:]))

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [webSearchTool, codeInterpreterTool],
                providerOptions: [
                    "openai": [
                        "logprobs": .bool(true)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body for auto include test")
            return
        }

        let includeValues = Set((json["include"] as? [String]) ?? [])
        #expect(includeValues.contains("web_search_call.action.sources"))
        #expect(includeValues.contains("code_interpreter_call.outputs"))
        #expect(includeValues.contains("message.output_text.logprobs"))
        #expect(json["top_logprobs"] as? Int == TOP_LOGPROBS_MAX)
    }

    @Test("doStream emits web search tool results")
    func testDoStreamEmitsWebSearchResults() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "web_call",
                    "type": "web_search_call",
                    "status": "in_progress"
                ]
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "web_call",
                    "type": "web_search_call",
                    "status": "completed",
                    "action": [
                        "type": "search",
                        "query": "swift ai"
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_web",
                    "object": "response",
                    "created_at": 1_741_500_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 1,
                        "total_tokens": 3
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let webSearchTool = LanguageModelV3Tool.providerDefined(.init(id: "openai.web_search", name: "web_search", args: [:]))

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [webSearchTool]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolInputStart(let id, let name, _, let executed, _, _) = part {
                return id == "web_call" && name == "web_search" && executed == true
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolInputEnd(let id, _) = part {
                return id == "web_call"
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolCall(let call) = part {
                return call.toolCallId == "web_call" && call.toolName == "web_search" && call.providerExecuted == true
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolResult(let result) = part {
                return result.toolCallId == "web_call" && result.toolName == "web_search" && result.providerExecuted == true
            }
            return false
        })

        if let data = await capture.current(),
           let json = decodeRequestBody(data) {
            #expect(json["stream"] as? Bool == true)
        }
    }

    @Test("doStream aliases mcp_call toolCallId after mcp_approval_request")
    func testDoStreamAliasesMcpCallAfterApprovalRequest() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "mcp_req_item_1",
                    "type": "mcp_approval_request",
                    "name": "list_files",
                    "arguments": "{\"path\":\"/\"}",
                    "approval_request_id": "approval_1"
                ]
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 1,
                "item": [
                    "id": "mcp_item_2",
                    "type": "mcp_call",
                    "name": "list_files",
                    "arguments": "{\"path\":\"/\"}",
                    "server_label": "My MCP",
                    "approval_request_id": "approval_1",
                    "output": "ok",
                    "error": NSNull()
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_mcp_stream",
                    "object": "response",
                    "created_at": 1_741_600_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 1,
                        "total_tokens": 3
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: samplePrompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolCall(let call) = part {
                return call.toolCallId == "generated-0" && call.toolName == "mcp.list_files" && call.dynamic == true
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolApprovalRequest(let request) = part {
                return request.approvalId == "approval_1" && request.toolCallId == "generated-0"
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolResult(let result) = part {
                guard result.toolCallId == "generated-0",
                      result.toolName == "mcp.list_files",
                      result.providerExecuted == true else {
                    return false
                }
                return result.providerMetadata?["openai"]?["itemId"] == .string("mcp_item_2")
            }
            return false
        })
    }

    @Test("doStream emits reasoning summary parts with deltas")
    func testDoStreamEmitsReasoningSummary() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "reasoning_item",
                    "type": "reasoning",
                    "status": "in_progress",
                    "encrypted_content": "opaque"
                ]
            ]),
            chunk([
                "type": "response.reasoning_summary_part.added",
                "item_id": "reasoning_item",
                "summary_index": 1
            ]),
            chunk([
                "type": "response.reasoning_summary_text.delta",
                "item_id": "reasoning_item",
                "summary_index": 1,
                "delta": "Second step"
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "reasoning_item",
                    "type": "reasoning",
                    "status": "completed",
                    "encrypted_content": "opaque",
                    "summary": [
                        ["type": "summary_text", "text": "First step"],
                        ["type": "summary_text", "text": "Second step"]
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_reasoning_stream",
                    "object": "response",
                    "created_at": 1_741_600_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 2,
                        "total_tokens": 4
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: samplePrompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .reasoningStart(let id, _) = part { return id == "reasoning_item:0" }
            return false
        })
        #expect(parts.contains { part in
            if case .reasoningStart(let id, _) = part { return id == "reasoning_item:1" }
            return false
        })
        #expect(parts.contains { part in
            if case .reasoningDelta(let id, let delta, _) = part { return id == "reasoning_item:1" && delta == "Second step" }
            return false
        })
        #expect(parts.contains { part in
            if case .reasoningEnd(let id, _) = part { return id == "reasoning_item:0" }
            return false
        })
        #expect(parts.contains { part in
            if case .reasoningEnd(let id, _) = part { return id == "reasoning_item:1" }
            return false
        })
    }

    @Test("doStream emits reasoning-end early for summary parts when store is true")
    func testDoStreamReasoningSummaryPartDoneEmitsEarlyEndWhenStoreTrue() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "reasoning_item",
                    "type": "reasoning",
                    "status": "in_progress",
                    "encrypted_content": "opaque"
                ]
            ]),
            chunk([
                "type": "response.reasoning_summary_part.added",
                "item_id": "reasoning_item",
                "summary_index": 1
            ]),
            chunk([
                "type": "response.reasoning_summary_text.delta",
                "item_id": "reasoning_item",
                "summary_index": 1,
                "delta": "Second step"
            ]),
            chunk([
                "type": "response.reasoning_summary_part.done",
                "item_id": "reasoning_item",
                "summary_index": 1
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "reasoning_item",
                    "type": "reasoning",
                    "status": "completed",
                    "encrypted_content": "opaque",
                    "summary": [
                        ["type": "summary_text", "text": "First step"],
                        ["type": "summary_text", "text": "Second step"]
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_reasoning_stream",
                    "object": "response",
                    "created_at": 1_741_600_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 2,
                        "total_tokens": 4
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: samplePrompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        let end1Parts = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningEnd(let id, let metadata) = part, id == "reasoning_item:1" {
                return metadata
            }
            return nil
        }
        #expect(end1Parts.count == 1)
        #expect(end1Parts.first?["openai"]?["reasoningEncryptedContent"] == nil)

        let end1Index = parts.firstIndex { part in
            if case .reasoningEnd(let id, _) = part { return id == "reasoning_item:1" }
            return false
        }
        let end0Index = parts.firstIndex { part in
            if case .reasoningEnd(let id, _) = part { return id == "reasoning_item:0" }
            return false
        }
        #expect(end1Index != nil)
        #expect(end0Index != nil)
        #expect(end1Index! < end0Index!)

        let end0Metadata = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningEnd(let id, let metadata) = part, id == "reasoning_item:0" {
                return metadata
            }
            return nil
        }.first

        #expect(end0Metadata?["openai"]?["reasoningEncryptedContent"] == .string("opaque"))
    }

    @Test("doStream concludes can-conclude reasoning parts when store is false and new part starts")
    func testDoStreamReasoningSummaryPartDoneConcludesOnNextPartWhenStoreFalse() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "reasoning_item",
                    "type": "reasoning",
                    "status": "in_progress"
                ]
            ]),
            chunk([
                "type": "response.reasoning_summary_part.added",
                "item_id": "reasoning_item",
                "summary_index": 1
            ]),
            chunk([
                "type": "response.reasoning_summary_text.delta",
                "item_id": "reasoning_item",
                "summary_index": 1,
                "delta": "Second step"
            ]),
            chunk([
                "type": "response.reasoning_summary_part.done",
                "item_id": "reasoning_item",
                "summary_index": 1
            ]),
            chunk([
                "type": "response.reasoning_summary_part.added",
                "item_id": "reasoning_item",
                "summary_index": 2
            ]),
            chunk([
                "type": "response.reasoning_summary_text.delta",
                "item_id": "reasoning_item",
                "summary_index": 2,
                "delta": "Third step"
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "reasoning_item",
                    "type": "reasoning",
                    "status": "completed",
                    "encrypted_content": "opaque_final",
                    "summary": [
                        ["type": "summary_text", "text": "First step"],
                        ["type": "summary_text", "text": "Second step"],
                        ["type": "summary_text", "text": "Third step"]
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_reasoning_stream",
                    "object": "response",
                    "created_at": 1_741_600_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 2,
                        "total_tokens": 4
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "store": .bool(false)
                    ]
                ]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        // When store is false, reasoning_item:1 should be concluded when the next part (2) starts,
        // without encrypted content.
        let end1Parts = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningEnd(let id, let metadata) = part, id == "reasoning_item:1" {
                return metadata
            }
            return nil
        }
        #expect(end1Parts.count == 1)
        #expect(end1Parts.first?["openai"]?["reasoningEncryptedContent"] == nil)

        let end1Index = parts.firstIndex { part in
            if case .reasoningEnd(let id, _) = part { return id == "reasoning_item:1" }
            return false
        }
        let start2Index = parts.firstIndex { part in
            if case .reasoningStart(let id, _) = part { return id == "reasoning_item:2" }
            return false
        }
        #expect(end1Index != nil)
        #expect(start2Index != nil)
        #expect(end1Index! < start2Index!)

        // The remaining reasoning parts should be concluded at output_item.done with encrypted content from the done item.
        let end0Metadata = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningEnd(let id, let metadata) = part, id == "reasoning_item:0" {
                return metadata
            }
            return nil
        }.first
        #expect(end0Metadata?["openai"]?["reasoningEncryptedContent"] == .string("opaque_final"))

        let end2Metadata = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningEnd(let id, let metadata) = part, id == "reasoning_item:2" {
                return metadata
            }
            return nil
        }.first
        #expect(end2Metadata?["openai"]?["reasoningEncryptedContent"] == .string("opaque_final"))
    }

    @Test("doGenerate maps incomplete length finish reason")
    func testDoGenerateIncompleteLengthFinishReason() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_incomplete_length",
            "created_at": 1_742_250_000.0,
            "model": "gpt-4o",
            "output": [],
            "service_tier": NSNull(),
            "usage": ["input_tokens": 2, "output_tokens": 2, "total_tokens": 4],
            "warnings": [],
            "incomplete_details": ["reason": "max_output_tokens"],
            "finish_reason": "length",
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))
        #expect(result.finishReason == .length)
    }

    @Test("doStream maps incomplete finish reason")
    func testDoStreamIncompleteFinishReason() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "msg_incomplete",
                    "type": "message",
                    "status": "in_progress",
                    "role": "assistant",
                    "content": []
                ]
            ]),
            chunk([
                "type": "response.incomplete",
                "response": [
                    "id": "resp_incomplete_stream",
                    "object": "response",
                    "created_at": 1_742_260_000.0,
                    "status": "incomplete",
                    "incomplete_details": ["reason": "max_output_tokens"],
                    "usage": ["input_tokens": 3, "output_tokens": 3, "total_tokens": 6]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        var finishPart: LanguageModelV3StreamPart?
        for try await part in streamResult.stream {
            finishPart = part
        }

        if case .finish(let reason, let usage, _) = finishPart {
            #expect(reason == .length)
            #expect(usage.totalTokens == 6)
        } else {
            Issue.record("Expected finish part for incomplete stream")
        }
    }

    @Test("doStream emits code interpreter results")
    func testDoStreamEmitsCodeInterpreterResults() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "code_call",
                    "type": "code_interpreter_call",
                    "status": "in_progress",
                    "container_id": "container-7"
                ]
            ]),
            chunk([
                "type": "response.code_interpreter_call_code.delta",
                "output_index": 0,
                "delta": "print(\"Hi\")"
            ]),
            chunk([
                "type": "response.code_interpreter_call_code.done",
                "output_index": 0,
                "code": "print(\"Hi\")"
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "code_call",
                    "type": "code_interpreter_call",
                    "status": "completed",
                    "container_id": "container-7",
                    "outputs": [
                        ["type": "logs", "content": "Hi"]
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_code",
                    "object": "response",
                    "created_at": 1_741_700_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 2,
                        "total_tokens": 4
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.code_interpreter", name: "code_interpreter", args: [:]))

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolInputStart(let id, let name, _, let executed, _, _) = part {
                return id == "code_call" && name == "code_interpreter" && executed == true
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolInputDelta(let id, let delta, _) = part {
                return id == "code_call" && delta.hasPrefix("{\"containerId\":\"container-7\",\"code\":\"")
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolInputEnd(let id, _) = part { return id == "code_call" }
            return false
        })

        #expect(parts.contains { part in
            if case .toolCall(let call) = part {
                return call.toolCallId == "code_call" && call.toolName == "code_interpreter" && call.providerExecuted == true
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolResult(let result) = part {
                if result.toolCallId == "code_call" && result.toolName == "code_interpreter" && result.providerExecuted == true {
                    if case .object(let payload) = result.result,
                       let outputs = payload["outputs"], case .array(let array) = outputs {
                        return !array.isEmpty
                    }
                }
            }
            return false
        })

        if let finish = parts.last, case .finish(let reason, let usage, _) = finish {
            #expect(reason == .stop)
            #expect(usage.totalTokens == 4)
        } else {
            Issue.record("Expected finish part for code interpreter stream")
        }
    }

    @Test("doStream emits image generation partial results")
    func testDoStreamEmitsImageGenerationPartial() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "image_call",
                    "type": "image_generation_call",
                    "status": "in_progress"
                ]
            ]),
            chunk([
                "type": "response.image_generation_call.partial_image",
                "item_id": "image_call",
                "partial_image_b64": "partial-data"
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "image_call",
                    "type": "image_generation_call",
                    "status": "completed",
                    "result": "final-data"
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_image",
                    "object": "response",
                    "created_at": 1_741_800_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 2,
                        "total_tokens": 4
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5-nano",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.image_generation", name: "image_generation", args: [:]))

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolResult(let result) = part {
                if result.toolCallId == "image_call" && result.toolName == "image_generation" {
                    return result.preliminary == true
                }
            }
            return false
        })
    }

    @Test("doStream emits file search results")
    func testDoStreamEmitsFileSearchResults() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "file_call",
                    "type": "file_search_call",
                    "status": "in_progress"
                ]
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "file_call",
                    "type": "file_search_call",
                    "status": "completed",
                    "queries": ["swift"],
                    "results": [
                        [
                            "attributes": ["kind": "document"],
                            "file_id": "file-123",
                            "filename": "doc.txt",
                            "score": 0.9,
                            "text": "Result text"
                        ]
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_file",
                    "object": "response",
                    "created_at": 1_741_900_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 3,
                        "output_tokens": 1,
                        "total_tokens": 4
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.file_search", name: "file_search", args: ["vectorStoreIds": .array([.string("vs_1")])]))

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolResult(let result) = part {
                if result.toolCallId == "file_call" && result.toolName == "file_search" && result.providerExecuted == true {
                    if case .object(let payload) = result.result,
                       let res = payload["results"], case .array(let array) = res {
                        return array.count == 1
                    }
                }
            }
            return false
        })
    }

    @Test("doStream yields raw chunks and error events")
    func testDoStreamEmitsRawChunksAndError() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.created",
                "response": [
                    "id": "resp_error",
                    "object": "response",
                    "created_at": 1_742_000_000.0,
                    "status": "in_progress",
                    "model": "gpt-4o"
                ]
            ]),
            chunk([
                "type": "error",
                "code": "ERR_SOMETHING",
                "message": "Something went wrong"
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                includeRawChunks: true
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .raw(let raw) = part {
                if case .object(let object) = raw {
                    return object["type"] == .string("error")
                }
            }
            return false
        })

        #expect(parts.contains { part in
            if case .error(let error) = part {
                if case .object(let object) = error {
                    return object["message"] == .string("Something went wrong")
                }
            }
            return false
        })

        if let finish = parts.last, case .finish(let reason, _, _) = finish {
            #expect(reason == .error)
        } else {
            Issue.record("Expected finish error part")
        }
    }


    @Test("doStream emits computer use results")
    func testDoStreamEmitsComputerUseResults() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "computer_call",
                    "type": "computer_call",
                    "status": "in_progress"
                ]
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "computer_call",
                    "type": "computer_call",
                    "status": "completed"
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_computer",
                    "object": "response",
                    "created_at": 1_742_100_000.0,
                    "status": "completed",
                    "usage": [
                        "input_tokens": 2,
                        "output_tokens": 1,
                        "total_tokens": 3
                    ]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.computer_use", name: "computer_use", args: [:]))

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolInputStart(let id, let name, _, let executed, _, _) = part {
                return id == "computer_call" && name == "computer_use" && executed == true
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolInputEnd(let id, _) = part { return id == "computer_call" }
            return false
        })

        #expect(parts.contains { part in
            if case .toolCall(let call) = part {
                return call.toolCallId == "computer_call" && call.toolName == "computer_use" && call.providerExecuted == true
            }
            return false
        })

        #expect(parts.contains { part in
            if case .toolResult(let result) = part {
                if result.toolCallId == "computer_call" && result.toolName == "computer_use" && result.providerExecuted == true {
                    if case .object(let payload) = result.result {
                        return payload["type"] == .string("computer_use_tool_result")
                    }
                }
            }
            return false
        })
    }
    @Test("doStream emits local shell input")
    func testDoStreamEmitsLocalShellInput() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "shell_item",
                    "type": "local_shell_call",
                    "status": "in_progress",
                    "action": [
                        "type": "exec",
                        "command": []
                    ],
                    "call_id": "call_shell"
                ]
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "shell_item",
                    "type": "local_shell_call",
                    "status": "completed",
                    "action": [
                        "type": "exec",
                        "command": ["ls"],
                        "working_directory": "/tmp",
                        "env": [
                            "PATH": "/usr/bin"
                        ]
                    ],
                    "call_id": "call_shell"
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_shell",
                    "object": "response",
                    "created_at": 1_742_150_000.0,
                    "status": "completed",
                    "usage": ["input_tokens": 2, "output_tokens": 1, "total_tokens": 3]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.local_shell", name: "local_shell", args: [:]))

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .toolCall(let call) = part {
                return call.toolCallId == "call_shell" && call.toolName == "local_shell" && call.providerExecuted == nil
            }
            return false
        })
    }

    @Test("doGenerate maps apply_patch tool calls")
    func testDoGenerateMapsApplyPatchToolCall() async throws {
        actor BodyCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_apply_patch",
            "created_at": 1_742_250_000.0,
            "model": "gpt-4o",
            "output": [
                [
                    "id": "apc_1",
                    "type": "apply_patch_call",
                    "status": "completed",
                    "call_id": "call_apply",
                    "operation": [
                        "type": "delete_file",
                        "path": "obsolete.txt"
                    ]
                ]
            ],
            "service_tier": "default",
            "usage": [
                "input_tokens": 2,
                "output_tokens": 1,
                "output_tokens_details": ["reasoning_tokens": 0],
                "input_tokens_details": ["cached_tokens": 0]
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.apply_patch", name: "apply_patch", args: [:]))

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls.first?.toolCallId == "call_apply")
        #expect(toolCalls.first?.toolName == "apply_patch")
        #expect(toolCalls.first?.providerMetadata?["openai"]?["itemId"] == .string("apc_1"))

        if let input = toolCalls.first?.input,
           let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let callId = json["callId"] as? String,
           let operation = json["operation"] as? [String: Any] {
            #expect(callId == "call_apply")
            #expect(operation["type"] as? String == "delete_file")
            #expect(operation["path"] as? String == "obsolete.txt")
        } else {
            Issue.record("Expected apply_patch tool input JSON")
        }

        guard let request = await capture.current(),
              let body = decodeRequestBody(request.httpBody),
              let tools = body["tools"] as? [[String: Any]] else {
            Issue.record("Expected tools in request body")
            return
        }

        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "apply_patch")
    }

    @Test("doGenerate maps provider tool calls to custom tool names (apply_patch)")
    func testDoGenerateMapsApplyPatchCustomToolName() async throws {
        actor BodyCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_apply_patch",
            "created_at": 1_742_250_000.0,
            "model": "gpt-4o",
            "output": [
                [
                    "id": "apc_1",
                    "type": "apply_patch_call",
                    "status": "completed",
                    "call_id": "call_apply",
                    "operation": [
                        "type": "delete_file",
                        "path": "obsolete.txt"
                    ]
                ]
            ],
            "service_tier": "default",
            "usage": [
                "input_tokens": 2,
                "output_tokens": 1,
                "output_tokens_details": ["reasoning_tokens": 0],
                "input_tokens_details": ["cached_tokens": 0]
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.apply_patch", name: "my_apply_patch", args: [:]))

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls.first?.toolCallId == "call_apply")
        #expect(toolCalls.first?.toolName == "my_apply_patch")
        #expect(toolCalls.first?.providerMetadata?["openai"]?["itemId"] == .string("apc_1"))

        guard let request = await capture.current(),
              let body = decodeRequestBody(request.httpBody),
              let tools = body["tools"] as? [[String: Any]] else {
            Issue.record("Expected tools in request body")
            return
        }

        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "apply_patch")
    }

    @Test("doStream emits apply_patch tool input and tool call")
    func testDoStreamEmitsApplyPatchToolCall() async throws {
        func chunk(_ value: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value)
            let encoded = String(data: data, encoding: .utf8)!
            return "data:\(encoded)\n\n"
        }

        let chunks: [String] = [
            chunk([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "apc_1",
                    "type": "apply_patch_call",
                    "status": "in_progress",
                    "call_id": "call_apply",
                    "operation": [
                        "type": "create_file",
                        "path": "shopping-checklist.md",
                        "diff": ""
                    ]
                ]
            ]),
            chunk([
                "type": "response.apply_patch_call_operation_diff.delta",
                "output_index": 0,
                "delta": "+Hello"
            ]),
            chunk([
                "type": "response.apply_patch_call_operation_diff.done",
                "output_index": 0,
                "diff": "+Hello"
            ]),
            chunk([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": "apc_1",
                    "type": "apply_patch_call",
                    "status": "completed",
                    "call_id": "call_apply",
                    "operation": [
                        "type": "create_file",
                        "path": "shopping-checklist.md",
                        "diff": "+Hello"
                    ]
                ]
            ]),
            chunk([
                "type": "response.completed",
                "response": [
                    "id": "resp_apply_patch",
                    "object": "response",
                    "created_at": 1_742_250_000.0,
                    "status": "completed",
                    "usage": ["input_tokens": 2, "output_tokens": 1, "total_tokens": 3]
                ]
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.providerDefined(.init(id: "openai.apply_patch", name: "apply_patch", args: [:]))

        let streamResult = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                tools: [tool]
            )
        )

        var inputDeltas: [String] = []
        var toolInputEnded = false
        var toolCall: LanguageModelV3ToolCall?

        for try await part in streamResult.stream {
            switch part {
            case .toolInputDelta(let id, let delta, _):
                if id == "call_apply" {
                    inputDeltas.append(delta)
                }
            case .toolInputEnd(let id, _):
                if id == "call_apply" { toolInputEnded = true }
            case .toolCall(let call):
                if call.toolCallId == "call_apply" {
                    toolCall = call
                }
            default:
                break
            }
        }

        #expect(toolInputEnded)
        #expect(toolCall?.toolName == "apply_patch")
        #expect(toolCall?.providerMetadata?["openai"]?["itemId"] == .string("apc_1"))

        guard let toolCall else {
            Issue.record("Missing apply_patch tool call")
            return
        }

        let deltasString = inputDeltas.joined()
        let deltasObject = try JSONSerialization.jsonObject(with: Data(deltasString.utf8))
        let toolCallObject = try JSONSerialization.jsonObject(with: Data(toolCall.input.utf8))

        #expect(try jsonValue(from: deltasObject) == jsonValue(from: toolCallObject))
    }


    @Test("doGenerate forwards previousResponseId and metadata")
    func testDoGeneratePreviousResponseId() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_prev",
            "created_at": 1_742_200_000.0,
            "model": "gpt-4o",
            "output": [],
            "service_tier": "default",
            "usage": ["input_tokens": 2, "output_tokens": 1, "total_tokens": 3],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "previousResponseId": .string("resp_old"),
                        "metadata": .object(["context": .string("test")]),
                        "serviceTier": .string("priority"),
                        "user": .string("test-user")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body for previousResponseId test")
            return
        }

        #expect(json["previous_response_id"] as? String == "resp_old")
        if let metadata = json["metadata"] as? [String: Any] {
            #expect(metadata["context"] as? String == "test")
        } else {
            Issue.record("Expected metadata in request")
        }
        #expect(json["service_tier"] as? String == "priority")
        #expect(json["user"] as? String == "test-user")
    }

    @Test("doGenerate forwards conversation provider option")
    func testDoGenerateConversation() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_conv",
            "created_at": 1_742_200_000.0,
            "model": "gpt-4o",
            "output": [],
            "service_tier": "default",
            "usage": ["input_tokens": 2, "output_tokens": 1, "total_tokens": 3],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "conversation": .string("conv_123")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body for conversation test")
            return
        }

        #expect(json["conversation"] as? String == "conv_123")
    }

    @Test("doGenerate warns when both conversation and previousResponseId are provided")
    func testDoGenerateWarnsOnConversationAndPreviousResponseId() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_conflict",
            "created_at": 1_742_200_000.0,
            "model": "gpt-4o",
            "output": [],
            "service_tier": "default",
            "usage": ["input_tokens": 2, "output_tokens": 1, "total_tokens": 3],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "conversation": .string("conv_123"),
                        "previousResponseId": .string("resp_old")
                    ]
                ]
            )
        )

        #expect(
            result.warnings.contains(
                .unsupportedSetting(
                    setting: "conversation",
                    details: "conversation and previousResponseId cannot be used together"
                )
            )
        )
    }

    // MARK: - Missing Basic Tests (lines 161-250)

    @Test("should generate text")
    func testShouldGenerateText() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1_741_257_730.0,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "model": "gpt-4o-2024-07-18",
            "output": [
                [
                    "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "answer text",
                            "annotations": [],
                            "logprobs": []
                        ]
                    ]
                ]
            ],
            "usage": [
                "input_tokens": 345,
                "input_tokens_details": ["cached_tokens": 234],
                "output_tokens": 538,
                "output_tokens_details": ["reasoning_tokens": 123],
                "total_tokens": 883
            ],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.content.contains { content in
            if case .text(let text) = content {
                return text.text == "answer text"
            }
            return false
        })

        if let textContent = result.content.first, case .text(let text) = textContent {
            if let metadata = text.providerMetadata?["openai"] {
                #expect(metadata["itemId"] == .string("msg_67c97c02656c81908e080dfdf4a03cd1"))
            }
        }
    }

    @Test("should extract usage")
    func testShouldExtractUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_usage",
            "object": "response",
            "created_at": 1_741_257_730.0,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "model": "gpt-4o",
            "output": [],
            "usage": [
                "input_tokens": 345,
                "input_tokens_details": ["cached_tokens": 234],
                "output_tokens": 538,
                "output_tokens_details": ["reasoning_tokens": 123],
                "total_tokens": 883
            ],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.usage.inputTokens == 345)
        #expect(result.usage.outputTokens == 538)
        #expect(result.usage.totalTokens == 883)
        #expect(result.usage.cachedInputTokens == 234)
        #expect(result.usage.reasoningTokens == 123)
    }

    @Test("should extract response id metadata")
    func testShouldExtractResponseIdMetadata() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1_741_257_730.0,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        if let openaiMetadata = result.providerMetadata?["openai"] {
            #expect(openaiMetadata["responseId"] == .string("resp_67c97c0203188190a025beb4a75242bc"))
        } else {
            Issue.record("Missing openai provider metadata")
        }
    }

    @Test("should send model id, settings, and input")
    func testShouldSendModelIdSettingsAndInput() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_settings",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [
                    .system(content: "You are a helpful assistant.", providerOptions: nil),
                    .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
                ],
                temperature: 0.5,
                topP: 0.3,
                providerOptions: [
                    "openai": [
                        "maxToolCalls": .number(10)
                    ]
                ]
            )
        )

        #expect(result.warnings.isEmpty)

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["model"] as? String == "gpt-4o")
        #expect(json["temperature"] as? Double == 0.5)
        #expect(json["top_p"] as? Double == 0.3)
        #expect(json["max_tool_calls"] as? Int == 10)

        if let input = json["input"] as? [[String: Any]] {
            #expect(input.count == 2)
            #expect(input[0]["role"] as? String == "system")
            if let content = input[0]["content"] as? String {
                #expect(content == "You are a helpful assistant.")
            } else if let contentArray = input[0]["content"] as? [[String: Any]] {
                if let first = contentArray.first, let text = first["text"] as? String {
                    #expect(text == "You are a helpful assistant.")
                }
            }
            #expect(input[1]["role"] as? String == "user")
        } else {
            Issue.record("Missing input array")
        }
    }

    @Test("should remove unsupported settings for o1")
    func testShouldRemoveUnsupportedSettingsForO1() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_o1",
            "created_at": 1_700_000_000.0,
            "model": "o1-mini",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o1-mini",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [
                    .system(content: "You are a helpful assistant.", providerOptions: nil),
                    .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
                ],
                temperature: 0.5,
                topP: 0.3
            )
        )

        #expect(result.warnings.count >= 2)
        #expect(result.warnings.contains { warning in
            if case let .unsupportedSetting(setting, _) = warning {
                return setting == "temperature"
            }
            return false
        })
        #expect(result.warnings.contains { warning in
            if case let .unsupportedSetting(setting, _) = warning {
                return setting == "topP"
            }
            return false
        })

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["model"] as? String == "o1-mini")
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)

        if let input = json["input"] as? [[String: Any]] {
            #expect(input.count == 2)
            #expect(input[0]["role"] as? String == "developer")
            if let content = input[0]["content"] as? String {
                #expect(content == "You are a helpful assistant.")
            }
            #expect(input[1]["role"] as? String == "user")
        }
    }

    // MARK: - Response Format Tests (lines 352-441)

    @Test("should send response format json schema")
    func testShouldSendResponseFormatJsonSchema() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_json_schema",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let schema: JSONValue = .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": .string("string")])
            ]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false)
        ])

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                responseFormat: .json(schema: schema, name: "response", description: "A response")
            )
        )

        #expect(result.warnings.isEmpty)

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any],
              let format = text["format"] as? [String: Any] else {
            Issue.record("Missing text format in request")
            return
        }

        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "response")
        #expect(format["description"] as? String == "A response")
        #expect(format["strict"] as? Bool == true)
        #expect(format["schema"] != nil)
    }

    @Test("should send response format json object")
    func testShouldSendResponseFormatJsonObject() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_json_obj",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                responseFormat: .json(schema: nil, name: nil, description: nil)
            )
        )

        #expect(result.warnings.isEmpty)

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any],
              let format = text["format"] as? [String: Any] else {
            Issue.record("Missing text format in request")
            return
        }

        #expect(format["type"] as? String == "json_object")
    }

    // MARK: - Provider Options Tests (lines 443-622)

    @Test("should send parallelToolCalls provider option")
    func testShouldSendParallelToolCallsProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_parallel",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "parallelToolCalls": .bool(false)
                    ]
                ]
            )
        )

        #expect(result.warnings.isEmpty)

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["parallel_tool_calls"] as? Bool == false)
    }

    @Test("should send store = false provider option and opt into reasoning.encrypted_content for reasoning models")
    func testShouldSendStoreFalseForReasoningModels() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_store_reasoning",
            "created_at": 1_700_000_000.0,
            "model": "gpt-5-mini",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5-mini",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "store": .bool(false)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["store"] as? Bool == false)

        if let include = json["include"] as? [String] {
            #expect(include.contains("reasoning.encrypted_content"))
        } else {
            Issue.record("Missing include for reasoning model with store=false")
        }
    }

    @Test("should send store = false provider option and not opt into reasoning.encrypted_content for non-reasoning models")
    func testShouldSendStoreFalseForNonReasoningModels() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_store_standard",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "store": .bool(false)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["store"] as? Bool == false)

        if let include = json["include"] as? [String] {
            #expect(!include.contains("reasoning.encrypted_content"))
        }
    }

    @Test("should send store = true provider option without reasoning.encrypted_content")
    func testShouldSendStoreTrueWithoutReasoningContent() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_store_true",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "store": .bool(true)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["store"] as? Bool == true)

        if let include = json["include"] as? [String] {
            #expect(!include.contains("reasoning.encrypted_content"))
        }
    }

    @Test("should send user provider option")
    func testShouldSendUserProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_user",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "user": .string("test-user-123")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["user"] as? String == "test-user-123")
    }

    @Test("should send previous response id provider option")
    func testShouldSendPreviousResponseIdProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_new",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "previousResponseId": .string("resp_previous_123")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["previous_response_id"] as? String == "resp_previous_123")
    }

    @Test("should send metadata provider option")
    func testShouldSendMetadataProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_metadata",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "metadata": .object([
                            "userId": .string("user-456"),
                            "sessionId": .string("session-789")
                        ])
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let metadata = json["metadata"] as? [String: Any] else {
            Issue.record("Missing metadata in request")
            return
        }

        #expect(metadata["userId"] as? String == "user-456")
        #expect(metadata["sessionId"] as? String == "session-789")
    }

    // MARK: - Additional Provider Options (lines 707-914)

    @Test("should send instructions provider option")
    func testShouldSendInstructionsProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_instructions",
            "created_at": 1_700_000_000.0,
            "model": "o3-mini",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "instructions": .string("Be very concise")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["instructions"] as? String == "Be very concise")
    }

    @Test("should send include provider option")
    func testShouldSendIncludeProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_include",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "include": .array([.string("reasoning.encrypted_content")])
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let include = json["include"] as? [String] else {
            Issue.record("Missing include in request")
            return
        }

        #expect(include.contains("reasoning.encrypted_content"))
    }

    @Test("should send include provider option with multiple values")
    func testShouldSendIncludeWithMultipleValues() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_include_multi",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "include": .array([
                            .string("reasoning.encrypted_content"),
                            .string("file_search_call.results")
                        ])
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let include = json["include"] as? [String] else {
            Issue.record("Missing include in request")
            return
        }

        #expect(Set(include) == Set(["reasoning.encrypted_content", "file_search_call.results"]))
    }

    @Test("should send textVerbosity provider option - low")
    func testShouldSendTextVerbosityLow() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_verbosity",
            "created_at": 1_700_000_000.0,
            "model": "gpt-5",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "textVerbosity": .string("low")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any] else {
            Issue.record("Missing text payload")
            return
        }

        #expect(text["verbosity"] as? String == "low")
    }

    @Test("should send textVerbosity provider option - medium")
    func testShouldSendTextVerbosityMedium() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_verbosity_med",
            "created_at": 1_700_000_000.0,
            "model": "gpt-5",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "textVerbosity": .string("medium")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any] else {
            Issue.record("Missing text payload")
            return
        }

        #expect(text["verbosity"] as? String == "medium")
    }

    @Test("should send textVerbosity provider option - high")
    func testShouldSendTextVerbosityHigh() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_verbosity_high",
            "created_at": 1_700_000_000.0,
            "model": "gpt-5",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "textVerbosity": .string("high")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any] else {
            Issue.record("Missing text payload")
            return
        }

        #expect(text["verbosity"] as? String == "high")
    }

    @Test("should send promptCacheKey provider option")
    func testShouldSendPromptCacheKeyProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_cache_key",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "promptCacheKey": .string("cache-key-123")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["prompt_cache_key"] as? String == "cache-key-123")
    }

    @Test("should send safetyIdentifier provider option")
    func testShouldSendSafetyIdentifierProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_safety",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "safetyIdentifier": .string("safety-id-456")
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["safety_identifier"] as? String == "safety-id-456")
    }

    @Test("should send logprobs provider option")
    func testShouldSendLogprobsProviderOption() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_logprobs_opt",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "logprobs": .bool(true)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()) else {
            Issue.record("Missing request body")
            return
        }

        if let include = json["include"] as? [String] {
            #expect(include.contains("message.output_text.logprobs"))
        } else {
            Issue.record("Missing include for logprobs")
        }
        #expect(json["top_logprobs"] as? Int == TOP_LOGPROBS_MAX)
    }

    // MARK: - Response Format Additional Tests (lines 936-1061)

    @Test("should send responseFormat json format")
    func testShouldSendResponseFormatJson() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_response_format",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                responseFormat: .json(schema: nil, name: nil, description: nil)
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any],
              let format = text["format"] as? [String: Any] else {
            Issue.record("Missing text format in request")
            return
        }

        #expect(format["type"] as? String == "json_object")
    }

    @Test("should send responseFormat json_schema format")
    func testShouldSendResponseFormatJsonSchemaFormat() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_json_schema_format",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let schema: JSONValue = .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": .string("string")])
            ]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false)
        ])

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                responseFormat: .json(schema: schema, name: "MyResponse", description: "Test response")
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any],
              let format = text["format"] as? [String: Any] else {
            Issue.record("Missing text format in request")
            return
        }

        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "MyResponse")
        #expect(format["description"] as? String == "Test response")
        #expect(format["strict"] as? Bool == true)
    }

    @Test("should send responseFormat json_schema format with strictJsonSchema false")
    func testShouldSendResponseFormatJsonSchemaWithStrictJsonSchemaFalse() async throws {
        actor BodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = BodyCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_strict_false",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": .string("string")])
            ])
        ])

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                responseFormat: .json(schema: schema, name: "test", description: nil),
                providerOptions: [
                    "openai": [
                        "strictJsonSchema": .bool(false)
                    ]
                ]
            )
        )

        guard let json = decodeRequestBody(await capture.current()),
              let text = json["text"] as? [String: Any],
              let format = text["format"] as? [String: Any] else {
            Issue.record("Missing text format in request")
            return
        }

        #expect(format["strict"] as? Bool == false)
    }

    @Test("should warn about unsupported settings")
    func testShouldWarnAboutUnsupportedSettings() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_warn_unsupported",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": [
                [
                    "type": "unsupported-setting",
                    "setting": "temperature",
                    "message": "temperature is not supported"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.warnings.count == 1)
        if let warning = result.warnings.first {
            if case let .unsupportedSetting(setting, details) = warning {
                #expect(setting == "temperature")
                #expect(details == "temperature is not supported")
            } else {
                Issue.record("Expected unsupported-setting warning")
            }
        }
    }

    @Test("should extract logprobs in providerMetadata")
    func testShouldExtractLogprobsInProviderMetadata() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_logprobs_meta",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [
                [
                    "id": "msg_logprobs",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Hello",
                            "annotations": [],
                            "logprobs": [
                                [
                                    "token": "Hello",
                                    "logprob": -0.5,
                                    "bytes": [72, 101, 108, 108, 111],
                                    "top_logprobs": []
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        if let openaiMetadata = result.providerMetadata?["openai"] {
            if case .array(let logprobs) = openaiMetadata["logprobs"] {
                #expect(!logprobs.isEmpty)
            }
        } else {
            Issue.record("Missing openai provider metadata")
        }
    }

    // MARK: - Reasoning Tests (lines 1208-1972)

    @Test("should handle reasoning with summary")
    func testShouldHandleReasoningWithSummary() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_reasoning_summary",
            "created_at": 1_700_000_000.0,
            "model": "o3-mini",
            "output": [
                [
                    "id": "reasoning_1",
                    "type": "reasoning",
                    "status": "completed",
                    "summary": [
                        ["type": "summary_text", "text": "First step of reasoning"],
                        ["type": "summary_text", "text": "Second step of reasoning"]
                    ],
                    "encrypted_content": "encrypted-data-here"
                ]
            ],
            "usage": ["input_tokens": 10, "output_tokens": 5, "total_tokens": 15],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        #expect(reasoningParts.count >= 1)
        #expect(reasoningParts.contains { $0.text.contains("First step") || $0.text.contains("Second step") })
    }

    @Test("should handle reasoning with empty summary")
    func testShouldHandleReasoningWithEmptySummary() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_reasoning_empty",
            "created_at": 1_700_000_000.0,
            "model": "o3-mini",
            "output": [
                [
                    "id": "reasoning_2",
                    "type": "reasoning",
                    "status": "completed",
                    "summary": [],
                    "encrypted_content": "encrypted-data"
                ]
            ],
            "usage": ["input_tokens": 5, "output_tokens": 3, "total_tokens": 8],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        #expect(reasoningParts.isEmpty || reasoningParts.allSatisfy { $0.text.isEmpty })
    }

    @Test("should handle encrypted content with summary")
    func testShouldHandleEncryptedContentWithSummary() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_encrypted",
            "created_at": 1_700_000_000.0,
            "model": "o3-mini",
            "output": [
                [
                    "id": "reasoning_enc",
                    "type": "reasoning",
                    "status": "completed",
                    "summary": [
                        ["type": "summary_text", "text": "Encrypted reasoning summary"]
                    ],
                    "encrypted_content": "base64-encrypted-content"
                ]
            ],
            "usage": ["input_tokens": 15, "output_tokens": 10, "total_tokens": 25],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.content.contains { content in
            if case .reasoning(let reasoning) = content {
                return reasoning.text.contains("Encrypted reasoning summary")
            }
            return false
        })
    }

    @Test("should handle encrypted content with empty summary")
    func testShouldHandleEncryptedContentWithEmptySummary() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_encrypted_empty",
            "created_at": 1_700_000_000.0,
            "model": "o3-mini",
            "output": [
                [
                    "id": "reasoning_enc_empty",
                    "type": "reasoning",
                    "status": "completed",
                    "summary": [],
                    "encrypted_content": "base64-encrypted"
                ]
            ],
            "usage": ["input_tokens": 8, "output_tokens": 4, "total_tokens": 12],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        #expect(reasoningParts.isEmpty || reasoningParts.allSatisfy { $0.text.isEmpty })
    }

    @Test("should handle multiple reasoning blocks")
    func testShouldHandleMultipleReasoningBlocks() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_multiple_reasoning",
            "created_at": 1_700_000_000.0,
            "model": "o3-mini",
            "output": [
                [
                    "id": "reasoning_a",
                    "type": "reasoning",
                    "status": "completed",
                    "summary": [
                        ["type": "summary_text", "text": "First block"]
                    ]
                ],
                [
                    "id": "reasoning_b",
                    "type": "reasoning",
                    "status": "completed",
                    "summary": [
                        ["type": "summary_text", "text": "Second block"]
                    ]
                ],
                [
                    "id": "reasoning_c",
                    "type": "reasoning",
                    "status": "completed",
                    "summary": [
                        ["type": "summary_text", "text": "Third block"]
                    ]
                ]
            ],
            "usage": ["input_tokens": 20, "output_tokens": 15, "total_tokens": 35],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "o3-mini",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        #expect(reasoningParts.count >= 3)
    }

    // MARK: - Tool Call Tests (lines 1972-2035)

    @Test("should generate tool calls")
    func testShouldGenerateToolCalls() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_tool_calls",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [
                [
                    "id": "tool_call_1",
                    "type": "function_call",
                    "status": "completed",
                    "name": "get_weather",
                    "call_id": "call_abc123",
                    "arguments": "{\"location\":\"San Francisco\"}"
                ]
            ],
            "usage": ["input_tokens": 50, "output_tokens": 20, "total_tokens": 70],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        #expect(toolCalls.count >= 1)
        #expect(toolCalls.contains { $0.toolName == "get_weather" && $0.toolCallId == "call_abc123" })
    }

    @Test("should have tool-calls finish reason")
    func testShouldHaveToolCallsFinishReason() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_tool_finish",
            "created_at": 1_700_000_000.0,
            "model": "gpt-4o",
            "output": [
                [
                    "id": "tool_call_2",
                    "type": "function_call",
                    "status": "completed",
                    "name": "search",
                    "call_id": "call_def456",
                    "arguments": "{\"query\":\"AI\"}"
                ]
            ],
            "finish_reason": "tool_calls",
            "usage": ["input_tokens": 30, "output_tokens": 15, "total_tokens": 45],
            "warnings": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.finishReason == .toolCalls)
    }

    // MARK: - fileIdPrefixes Configuration Tests
    // Port of openai-responses-language-model.test.ts: fileIdPrefixes configuration section

    @Test("fileIdPrefixes passes file IDs when prefix matches")
    func testFileIdPrefixesPassesFileIds() async throws {
        actor RequestCapture {
            var bodyData: Data?
            func store(_ data: Data?) { bodyData = data }
            func current() -> Data? { bodyData }
        }

        let capture = RequestCapture()
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let responseJSON: [String: Any] = [
                "id": "resp_test",
                "object": "response",
                "created_at": 1_741_257_730,
                "status": "completed",
                "model": "gpt-4o",
                "output": [
                    [
                        "id": "msg_test",
                        "type": "message",
                        "status": "completed",
                        "role": "assistant",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "I can see the image.",
                                "annotations": []
                            ]
                        ]
                    ]
                ],
                "usage": ["input_tokens": 10, "output_tokens": 5, "total_tokens": 15],
                "incomplete_details": NSNull()
            ]
            let responseData = try! JSONSerialization.data(withJSONObject: responseJSON)
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch, fileIdPrefixes: ["file-"])
        )

        let prompt: LanguageModelV3Prompt = [
            LanguageModelV3Message.user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Analyze this image")),
                    .file(LanguageModelV3FilePart(data: .base64("file-abc123"), mediaType: "image/jpeg"))
                ],
                providerOptions: nil
            )
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let bodyData = await capture.current(),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let input = json["input"] as? [[String: Any]],
              let firstMessage = input.first,
              let content = firstMessage["content"] as? [[String: Any]] else {
            Issue.record("Failed to extract request input")
            return
        }

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[1]["type"] as? String == "input_image")
        #expect(content[1]["file_id"] as? String == "file-abc123")
    }

    @Test("fileIdPrefixes handles multiple prefixes")
    func testFileIdPrefixesMultiplePrefixes() async throws {
        actor RequestCapture {
            var bodyData: Data?
            func store(_ data: Data?) { bodyData = data }
            func current() -> Data? { bodyData }
        }

        let capture = RequestCapture()
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let responseJSON: [String: Any] = [
                "id": "resp_test",
                "object": "response",
                "created_at": 1_741_257_730,
                "status": "completed",
                "model": "gpt-4o",
                "output": [
                    [
                        "id": "msg_test",
                        "type": "message",
                        "status": "completed",
                        "role": "assistant",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "I can see both images.",
                                "annotations": []
                            ]
                        ]
                    ]
                ],
                "usage": ["input_tokens": 10, "output_tokens": 5, "total_tokens": 15],
                "incomplete_details": NSNull()
            ]
            let responseData = try! JSONSerialization.data(withJSONObject: responseJSON)
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch, fileIdPrefixes: ["file-", "custom-"])
        )

        let prompt: LanguageModelV3Prompt = [
            LanguageModelV3Message.user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Compare these images")),
                    .file(LanguageModelV3FilePart(data: .base64("file-abc123"), mediaType: "image/jpeg")),
                    .file(LanguageModelV3FilePart(data: .base64("custom-xyz789"), mediaType: "image/jpeg"))
                ],
                providerOptions: nil
            )
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let bodyData = await capture.current(),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let input = json["input"] as? [[String: Any]],
              let firstMessage = input.first,
              let content = firstMessage["content"] as? [[String: Any]] else {
            Issue.record("Failed to extract request input")
            return
        }

        #expect(content.count == 3)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[1]["type"] as? String == "input_image")
        #expect(content[1]["file_id"] as? String == "file-abc123")
        #expect(content[2]["type"] as? String == "input_image")
        #expect(content[2]["file_id"] as? String == "custom-xyz789")
    }

    @Test("fileIdPrefixes falls back to base64 when undefined")
    func testFileIdPrefixesFallbackWhenUndefined() async throws {
        actor RequestCapture {
            var bodyData: Data?
            func store(_ data: Data?) { bodyData = data }
            func current() -> Data? { bodyData }
        }

        let capture = RequestCapture()
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let responseJSON: [String: Any] = [
                "id": "resp_test",
                "object": "response",
                "created_at": 1_741_257_730,
                "status": "completed",
                "model": "gpt-4o",
                "output": [
                    [
                        "id": "msg_test",
                        "type": "message",
                        "status": "completed",
                        "role": "assistant",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "I can see the image.",
                                "annotations": []
                            ]
                        ]
                    ]
                ],
                "usage": ["input_tokens": 10, "output_tokens": 5, "total_tokens": 15],
                "incomplete_details": NSNull()
            ]
            let responseData = try! JSONSerialization.data(withJSONObject: responseJSON)
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch, fileIdPrefixes: nil) // No fileIdPrefixes
        )

        let prompt: LanguageModelV3Prompt = [
            LanguageModelV3Message.user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Analyze this image")),
                    .file(LanguageModelV3FilePart(data: .base64("file-abc123"), mediaType: "image/jpeg"))
                ],
                providerOptions: nil
            )
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let bodyData = await capture.current(),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let input = json["input"] as? [[String: Any]],
              let firstMessage = input.first,
              let content = firstMessage["content"] as? [[String: Any]] else {
            Issue.record("Failed to extract request input")
            return
        }

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[1]["type"] as? String == "input_image")
        #expect(content[1]["image_url"] as? String == "data:image/jpeg;base64,file-abc123")
    }

    @Test("fileIdPrefixes falls back to base64 when prefix doesn't match")
    func testFileIdPrefixesFallbackWhenPrefixDoesNotMatch() async throws {
        actor RequestCapture {
            var bodyData: Data?
            func store(_ data: Data?) { bodyData = data }
            func current() -> Data? { bodyData }
        }

        let capture = RequestCapture()
        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let responseJSON: [String: Any] = [
                "id": "resp_test",
                "object": "response",
                "created_at": 1_741_257_730,
                "status": "completed",
                "model": "gpt-4o",
                "output": [
                    [
                        "id": "msg_test",
                        "type": "message",
                        "status": "completed",
                        "role": "assistant",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "I can see the image.",
                                "annotations": []
                            ]
                        ]
                    ]
                ],
                "usage": ["input_tokens": 10, "output_tokens": 5, "total_tokens": 15],
                "incomplete_details": NSNull()
            ]
            let responseData = try! JSONSerialization.data(withJSONObject: responseJSON)
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch, fileIdPrefixes: ["other-"]) // Different prefix
        )

        let prompt: LanguageModelV3Prompt = [
            LanguageModelV3Message.user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Analyze this image")),
                    .file(LanguageModelV3FilePart(data: .base64("file-abc123"), mediaType: "image/jpeg"))
                ],
                providerOptions: nil
            )
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let bodyData = await capture.current(),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let input = json["input"] as? [[String: Any]],
              let firstMessage = input.first,
              let content = firstMessage["content"] as? [[String: Any]] else {
            Issue.record("Failed to extract request input")
            return
        }

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[1]["type"] as? String == "input_image")
        #expect(content[1]["image_url"] as? String == "data:image/jpeg;base64,file-abc123")
    }

    // MARK: - Error Handling Tests
    // Port of openai-responses-language-model.test.ts: errors section

    @Test("should throw an API call error when the response contains an error part")
    func testShouldThrowAPICallErrorWhenResponseContainsErrorPart() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1_741_257_730,
            "status": "completed",
            "error": [
                "code": "ERR_SOMETHING",
                "message": "Something went wrong"
            ],
            "incomplete_details": NSNull(),
            "input": [],
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "model": "gpt-4o-2024-07-18",
            "output": [],
            "parallel_tool_calls": true,
            "previous_response_id": NSNull(),
            "reasoning": [
                "effort": NSNull(),
                "summary": NSNull()
            ],
            "store": true,
            "temperature": 1,
            "text": [
                "format": [
                    "type": "text"
                ]
            ],
            "tool_choice": "auto",
            "tools": [],
            "top_p": 1,
            "truncation": "disabled",
            "usage": [
                "input_tokens": 345,
                "input_tokens_details": ["cached_tokens": 234],
                "output_tokens": 538,
                "output_tokens_details": ["reasoning_tokens": 123],
                "total_tokens": 572
            ],
            "user": NSNull(),
            "metadata": [:]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            LanguageModelV3Message.user(
                content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                providerOptions: nil
            )
        ]

        do {
            _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))
            Issue.record("Expected error to be thrown")
        } catch let error as APICallError {
            #expect(error.message.contains("Something went wrong"))
        } catch {
            Issue.record("Expected APICallError, got \(type(of: error))")
        }
    }

    // Port of openai-responses-language-model.test.ts: "should handle both url_citation and file_citation annotations"
    @Test("should handle both url_citation and file_citation annotations")
    func testShouldHandleBothUrlCitationAndFileCitationAnnotations() async throws {
        let chunks = [
            #"data:{"type":"response.content_part.added","item_id":"msg_123","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}"# + "\n\n",
            #"data:{"type":"response.output_text.annotation.added","item_id":"msg_123","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"url_citation","url":"https://example.com","title":"Example URL","start_index":123,"end_index":234}}"# + "\n\n",
            #"data:{"type":"response.output_text.annotation.added","item_id":"msg_123","output_index":0,"content_index":0,"annotation_index":1,"annotation":{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}}"# + "\n\n",
            #"data:{"type":"response.content_part.done","item_id":"msg_123","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Based on web search and file content.","annotations":[{"type":"url_citation","start_index":0,"end_index":10,"url":"https://example.com","title":"Example URL"},{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}]}}"# + "\n\n",
            #"data:{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_123","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on web search and file content.","annotations":[{"type":"url_citation","start_index":0,"end_index":10,"url":"https://example.com","title":"Example URL"},{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}]}]}}"# + "\n\n",
            #"data:{"type":"response.completed","response":{"id":"resp_123","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_123","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on web search and file content.","annotations":[{"type":"url_citation","start_index":0,"end_index":10,"url":"https://example.com","title":"Example URL"},{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":100,"input_tokens_details":{"cached_tokens":0},"output_tokens":50,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":150},"user":null,"metadata":{}}}"# + "\n\n",
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        var order: [String] = []
        var urlSource: (id: String, url: String, title: String?)?
        var documentSource: (
            id: String,
            mediaType: String,
            title: String,
            filename: String?,
            providerMetadata: SharedV3ProviderMetadata?
        )?
        var textEnd: (id: String, providerMetadata: SharedV3ProviderMetadata?)?

        for try await chunk in result.stream {
            switch chunk {
            case .streamStart:
                order.append("stream-start")
            case .source(.url(let id, let url, let title, let providerMetadata)):
                order.append("source:url")
                urlSource = (id: id, url: url, title: title)
                #expect(providerMetadata == nil)
            case .source(.document(let id, let mediaType, let title, let filename, let providerMetadata)):
                order.append("source:document")
                documentSource = (
                    id: id,
                    mediaType: mediaType,
                    title: title,
                    filename: filename,
                    providerMetadata: providerMetadata
                )
            case .textEnd(let id, let providerMetadata):
                order.append("text-end")
                textEnd = (id: id, providerMetadata: providerMetadata)
            case .finish:
                order.append("finish")
            default:
                break
            }
        }

        #expect(order == [
            "stream-start",
            "source:url",
            "source:document",
            "text-end",
            "finish"
        ])

        if let urlSource {
            #expect(urlSource.id == "generated-0")
            #expect(urlSource.url == "https://example.com")
            #expect(urlSource.title == "Example URL")
        } else {
            Issue.record("Missing url source event")
        }

        if let documentSource {
            #expect(documentSource.id == "generated-1")
            #expect(documentSource.mediaType == "text/plain")
            #expect(documentSource.title == "resource1.json")
            #expect(documentSource.filename == "resource1.json")
            #expect(documentSource.providerMetadata == [
                "openai": [
                    "type": .string("file_citation"),
                    "fileId": .string("file-abc123"),
                    "index": 123
                ]
            ])
        } else {
            Issue.record("Missing document source event")
        }

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("url_citation"),
                "url": .string("https://example.com"),
                "title": .string("Example URL"),
                "start_index": 123,
                "end_index": 234
            ]),
            .object([
                "type": .string("file_citation"),
                "file_id": .string("file-abc123"),
                "filename": .string("resource1.json"),
                "index": 123
            ])
        ]

        if let textEnd {
            #expect(textEnd.id == "msg_123")
            #expect(textEnd.providerMetadata == [
                "openai": [
                    "itemId": .string("msg_123"),
                    "annotations": .array(expectedAnnotations)
                ]
            ])
        } else {
            Issue.record("Missing text-end event")
        }
    }

    // Port of openai-responses-language-model.test.ts: "should handle file_citation annotations without optional fields in streaming"
    @Test("should handle file_citation annotations without optional fields in streaming")
    func testShouldHandleFileCitationAnnotationsWithoutOptionalFieldsInStreaming() async throws {
        let chunks = [
            #"data:{"type":"response.content_part.added","item_id":"msg_456","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}"# + "\n\n",
            #"data:{"type":"response.output_text.annotation.added","item_id":"msg_456","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145}}"# + "\n\n",
            #"data:{"type":"response.output_text.annotation.added","item_id":"msg_456","output_index":0,"content_index":0,"annotation_index":1,"annotation":{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}}"# + "\n\n",
            #"data:{"type":"response.content_part.done","item_id":"msg_456","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Answer for the specified years....","annotations":[{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145},{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}]}}"# + "\n\n",
            #"data:{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_456","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Answer for the specified years....","annotations":[{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145},{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}]}]}}"# + "\n\n",
            #"data:{"type":"response.completed","response":{"id":"resp_456","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5","output":[{"id":"msg_456","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Answer for the specified years....","annotations":[{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145},{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":50,"input_tokens_details":{"cached_tokens":0},"output_tokens":25,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":75},"user":null,"metadata":{}}}"# + "\n\n",
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        var sources: [(
            id: String,
            mediaType: String,
            title: String,
            filename: String?,
            providerMetadata: SharedV3ProviderMetadata?
        )] = []
        var textEnd: (id: String, providerMetadata: SharedV3ProviderMetadata?)?

        for try await chunk in result.stream {
            switch chunk {
            case .source(.document(let id, let mediaType, let title, let filename, let providerMetadata)):
                sources.append((
                    id: id,
                    mediaType: mediaType,
                    title: title,
                    filename: filename,
                    providerMetadata: providerMetadata
                ))
            case .textEnd(let id, let providerMetadata):
                textEnd = (id: id, providerMetadata: providerMetadata)
            default:
                break
            }
        }

        #expect(sources.count == 2)

        if sources.count == 2 {
            #expect(sources[0].id == "generated-0")
            #expect(sources[0].mediaType == "text/plain")
            #expect(sources[0].title == "resource1.json")
            #expect(sources[0].filename == "resource1.json")
            #expect(sources[0].providerMetadata == [
                "openai": [
                    "type": .string("file_citation"),
                    "fileId": .string("file-YRcoCqn3Fo2K4JgraG"),
                    "index": 145
                ]
            ])

            #expect(sources[1].id == "generated-1")
            #expect(sources[1].mediaType == "text/plain")
            #expect(sources[1].title == "resource1.json")
            #expect(sources[1].filename == "resource1.json")
            #expect(sources[1].providerMetadata == [
                "openai": [
                    "type": .string("file_citation"),
                    "fileId": .string("file-YRcoCqn3Fo2K4JgraG"),
                    "index": 192
                ]
            ])
        }

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("file_citation"),
                "file_id": .string("file-YRcoCqn3Fo2K4JgraG"),
                "filename": .string("resource1.json"),
                "index": 145
            ]),
            .object([
                "type": .string("file_citation"),
                "file_id": .string("file-YRcoCqn3Fo2K4JgraG"),
                "filename": .string("resource1.json"),
                "index": 192
            ])
        ]

        if let textEnd {
            #expect(textEnd.id == "msg_456")
            #expect(textEnd.providerMetadata == [
                "openai": [
                    "itemId": .string("msg_456"),
                    "annotations": .array(expectedAnnotations)
                ]
            ])
        } else {
            Issue.record("Missing text-end event")
        }
    }


    // Port of openai-responses-language-model.test.ts: "should handle container_file_citation annotations in streaming"
    @Test("should handle container_file_citation annotations in streaming")
    func testShouldHandleContainerFileCitationAnnotationsInStreaming() async throws {
        let chunks = [
            #"data:{"type":"response.content_part.added","item_id":"msg_container","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}"# + "\n\n",
            #"data:{"type":"response.output_text.annotation.added","item_id":"msg_container","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"container_file_citation","container_id":"cntr_test","end_index":10,"file_id":"file-container","filename":"data.csv","start_index":0}}"# + "\n\n",
            #"data:{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_container","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Generated with container file.","annotations":[{"type":"container_file_citation","container_id":"cntr_test","file_id":"file-container","filename":"data.csv","start_index":0,"end_index":10}]}]}}"# + "\n\n",
            #"data:{"type":"response.completed","response":{"id":"resp_container","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5","output":[{"id":"msg_container","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Generated with container file.","annotations":[{"type":"container_file_citation","container_id":"cntr_test","file_id":"file-container","filename":"data.csv","start_index":0,"end_index":10}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":15},"user":null,"metadata":{}}}"# + "\n\n",
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        var documentSource: (
            id: String,
            mediaType: String,
            title: String,
            filename: String?,
            providerMetadata: SharedV3ProviderMetadata?
        )?
        var textEnd: (id: String, providerMetadata: SharedV3ProviderMetadata?)?

        for try await chunk in result.stream {
            switch chunk {
            case .source(.document(let id, let mediaType, let title, let filename, let providerMetadata)):
                documentSource = (
                    id: id,
                    mediaType: mediaType,
                    title: title,
                    filename: filename,
                    providerMetadata: providerMetadata
                )
            case .textEnd(let id, let providerMetadata):
                textEnd = (id: id, providerMetadata: providerMetadata)
            default:
                break
            }
        }

        if let documentSource {
            #expect(documentSource.id == "generated-0")
            #expect(documentSource.mediaType == "text/plain")
            #expect(documentSource.title == "data.csv")
            #expect(documentSource.filename == "data.csv")
            #expect(documentSource.providerMetadata == [
                "openai": [
                    "type": .string("container_file_citation"),
                    "fileId": .string("file-container"),
                    "containerId": .string("cntr_test")
                ]
            ])
        } else {
            Issue.record("Missing document source event")
        }

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("container_file_citation"),
                "container_id": .string("cntr_test"),
                "file_id": .string("file-container"),
                "filename": .string("data.csv"),
                "start_index": 0,
                "end_index": 10
            ])
        ]

        if let textEnd {
            #expect(textEnd.id == "msg_container")
            #expect(textEnd.providerMetadata == [
                "openai": [
                    "itemId": .string("msg_container"),
                    "annotations": .array(expectedAnnotations)
                ]
            ])
        } else {
            Issue.record("Missing text-end event")
        }
    }

    // Port of openai-responses-language-model.test.ts: "should handle file_path annotations in streaming"
    @Test("should handle file_path annotations in streaming")
    func testShouldHandleFilePathAnnotationsInStreaming() async throws {
        let chunks = [
            #"data:{"type":"response.content_part.added","item_id":"msg_file_path","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}"# + "\n\n",
            #"data:{"type":"response.output_text.annotation.added","item_id":"msg_file_path","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"file_path","file_id":"file-path-123","index":0}}"# + "\n\n",
            #"data:{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_file_path","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Output written to file.","annotations":[{"type":"file_path","file_id":"file-path-123","index":0}]}]}}"# + "\n\n",
            #"data:{"type":"response.completed","response":{"id":"resp_file_path","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_file_path","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Output written to file.","annotations":[{"type":"file_path","file_id":"file-path-123","index":0}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":15},"user":null,"metadata":{}}}"# + "\n\n",
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for string in chunks {
                    continuation.yield(Data(string.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        var documentSource: (
            id: String,
            mediaType: String,
            title: String,
            filename: String?,
            providerMetadata: SharedV3ProviderMetadata?
        )?
        var textEnd: (id: String, providerMetadata: SharedV3ProviderMetadata?)?

        for try await chunk in result.stream {
            switch chunk {
            case .source(.document(let id, let mediaType, let title, let filename, let providerMetadata)):
                documentSource = (
                    id: id,
                    mediaType: mediaType,
                    title: title,
                    filename: filename,
                    providerMetadata: providerMetadata
                )
            case .textEnd(let id, let providerMetadata):
                textEnd = (id: id, providerMetadata: providerMetadata)
            default:
                break
            }
        }

        if let documentSource {
            #expect(documentSource.id == "generated-0")
            #expect(documentSource.mediaType == "application/octet-stream")
            #expect(documentSource.title == "file-path-123")
            #expect(documentSource.filename == "file-path-123")
            #expect(documentSource.providerMetadata == [
                "openai": [
                    "type": .string("file_path"),
                    "fileId": .string("file-path-123"),
                    "index": 0
                ]
            ])
        } else {
            Issue.record("Missing document source event")
        }

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("file_path"),
                "file_id": .string("file-path-123"),
                "index": 0
            ])
        ]

        if let textEnd {
            #expect(textEnd.id == "msg_file_path")
            #expect(textEnd.providerMetadata == [
                "openai": [
                    "itemId": .string("msg_file_path"),
                    "annotations": .array(expectedAnnotations)
                ]
            ])
        } else {
            Issue.record("Missing text-end event")
        }
    }

    // Port of openai-responses-language-model.test.ts: "should handle mixed url_citation and file_citation annotations"
    @Test("should handle mixed url_citation and file_citation annotations")
    func testShouldHandleMixedUrlCitationAndFileCitationAnnotations() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "created_at": 1234567890,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "input": [],
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "model": "gpt-4o",
            "output": [
                [
                    "id": "msg_123",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Based on web search and file content.",
                            "annotations": [
                                [
                                    "type": "url_citation",
                                    "start_index": 0,
                                    "end_index": 10,
                                    "url": "https://example.com",
                                    "title": "Example URL"
                                ],
                                [
                                    "type": "file_citation",
                                    "file_id": "file-abc123",
                                    "filename": "resource1.json",
                                    "index": 123
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            "parallel_tool_calls": true,
            "previous_response_id": NSNull(),
            "reasoning": ["effort": NSNull(), "summary": NSNull()],
            "store": true,
            "temperature": 0,
            "text": ["format": ["type": "text"]],
            "tool_choice": "auto",
            "tools": [],
            "top_p": 1,
            "truncation": "disabled",
            "usage": [
                "input_tokens": 100,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens": 50,
                "output_tokens_details": ["reasoning_tokens": 0],
                "total_tokens": 150
            ],
            "user": NSNull(),
            "metadata": [:]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.content.count == 3)

        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text at index 0")
            return
        }
        #expect(text.text == "Based on web search and file content.")

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("url_citation"),
                "start_index": 0,
                "end_index": 10,
                "url": .string("https://example.com"),
                "title": .string("Example URL")
            ]),
            .object([
                "type": .string("file_citation"),
                "file_id": .string("file-abc123"),
                "filename": .string("resource1.json"),
                "index": 123
            ])
        ]

        #expect(text.providerMetadata == [
            "openai": [
                "itemId": .string("msg_123"),
                "annotations": .array(expectedAnnotations)
            ]
        ])

        guard case .source(.url(_, let url, let title, _)) = result.content[1] else {
            Issue.record("Expected url source at index 1")
            return
        }
        #expect(url == "https://example.com")
        #expect(title == "Example URL")

        guard case .source(.document(_, let mediaType, let docTitle, let filename, let providerMetadata)) = result.content[2] else {
            Issue.record("Expected document source at index 2")
            return
        }
        #expect(mediaType == "text/plain")
        #expect(docTitle == "resource1.json")
        #expect(filename == "resource1.json")
        #expect(providerMetadata == [
            "openai": [
                "type": .string("file_citation"),
                "fileId": .string("file-abc123"),
                "index": 123
            ]
        ])
    }

    // Port of openai-responses-language-model.test.ts: "should handle file_citation annotations only"
    @Test("should handle file_citation annotations only")
    func testShouldHandleFileCitationAnnotationsOnly() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_456",
            "object": "response",
            "created_at": 1234567890,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "input": [],
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "model": "gpt-4o",
            "output": [
                [
                    "id": "msg_456",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Based on the file content.",
                            "annotations": [
                                [
                                    "type": "file_citation",
                                    "file_id": "file-xyz789",
                                    "filename": "resource1.json",
                                    "index": 123
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            "parallel_tool_calls": true,
            "previous_response_id": NSNull(),
            "reasoning": ["effort": NSNull(), "summary": NSNull()],
            "store": true,
            "temperature": 0,
            "text": ["format": ["type": "text"]],
            "tool_choice": "auto",
            "tools": [],
            "top_p": 1,
            "truncation": "disabled",
            "usage": [
                "input_tokens": 50,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens": 25,
                "output_tokens_details": ["reasoning_tokens": 0],
                "total_tokens": 75
            ],
            "user": NSNull(),
            "metadata": [:]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.content.count == 2)

        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text at index 0")
            return
        }
        #expect(text.text == "Based on the file content.")

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("file_citation"),
                "file_id": .string("file-xyz789"),
                "filename": .string("resource1.json"),
                "index": 123
            ])
        ]

        #expect(text.providerMetadata == [
            "openai": [
                "itemId": .string("msg_456"),
                "annotations": .array(expectedAnnotations)
            ]
        ])

        guard case .source(.document(_, let mediaType, let title, let filename, let providerMetadata)) = result.content[1] else {
            Issue.record("Expected document source at index 1")
            return
        }
        #expect(mediaType == "text/plain")
        #expect(title == "resource1.json")
        #expect(filename == "resource1.json")
        #expect(providerMetadata == [
            "openai": [
                "type": .string("file_citation"),
                "fileId": .string("file-xyz789"),
                "index": 123
            ]
        ])
    }

    // Port of openai-responses-language-model.test.ts: "should handle file_citation annotations without optional fields"
    @Test("should handle file_citation annotations without optional fields")
    func testShouldHandleFileCitationAnnotationsWithoutOptionalFields() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_789",
            "object": "response",
            "created_at": 1234567890,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "input": [],
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "model": "gpt-4o",
            "output": [
                [
                    "id": "msg_789",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "The data shows trends.",
                            "annotations": [
                                [
                                    "type": "file_citation",
                                    "file_id": "file-YRcoCqn3Fo2K4JgraG",
                                    "filename": "resource1.json",
                                    "index": 145
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            "parallel_tool_calls": true,
            "previous_response_id": NSNull(),
            "reasoning": ["effort": NSNull(), "summary": NSNull()],
            "store": true,
            "temperature": 0,
            "text": ["format": ["type": "text"]],
            "tool_choice": "auto",
            "tools": [],
            "top_p": 1,
            "truncation": "disabled",
            "usage": [
                "input_tokens": 50,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens": 25,
                "output_tokens_details": ["reasoning_tokens": 0],
                "total_tokens": 75
            ],
            "user": NSNull(),
            "metadata": [:]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.content.count == 2)

        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text at index 0")
            return
        }
        #expect(text.text == "The data shows trends.")

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("file_citation"),
                "file_id": .string("file-YRcoCqn3Fo2K4JgraG"),
                "filename": .string("resource1.json"),
                "index": 145
            ])
        ]

        #expect(text.providerMetadata == [
            "openai": [
                "itemId": .string("msg_789"),
                "annotations": .array(expectedAnnotations)
            ]
        ])

        guard case .source(.document(_, let mediaType, let title, let filename, let providerMetadata)) = result.content[1] else {
            Issue.record("Expected document source at index 1")
            return
        }
        #expect(mediaType == "text/plain")
        #expect(title == "resource1.json")
        #expect(filename == "resource1.json")
        #expect(providerMetadata == [
            "openai": [
                "type": .string("file_citation"),
                "fileId": .string("file-YRcoCqn3Fo2K4JgraG"),
                "index": 145
            ]
        ])
    }

    // Port of openai-responses-language-model.test.ts: "should handle container_file_citation annotations"
    @Test("should handle container_file_citation annotations")
    func testShouldHandleContainerFileCitationAnnotations() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_container",
            "object": "response",
            "created_at": 1234567890,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "input": [],
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "model": "gpt-5",
            "output": [
                [
                    "id": "msg_container",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Generated with container file.",
                            "annotations": [
                                [
                                    "type": "container_file_citation",
                                    "container_id": "cntr_test",
                                    "file_id": "file-container",
                                    "filename": "data.csv",
                                    "start_index": 0,
                                    "end_index": 10,
                                    "index": 2
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            "parallel_tool_calls": true,
            "previous_response_id": NSNull(),
            "reasoning": ["effort": NSNull(), "summary": NSNull()],
            "store": true,
            "temperature": 0,
            "text": ["format": ["type": "text"]],
            "tool_choice": "auto",
            "tools": [],
            "top_p": 1,
            "truncation": "disabled",
            "usage": [
                "input_tokens": 10,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens": 5,
                "output_tokens_details": ["reasoning_tokens": 0],
                "total_tokens": 15
            ],
            "user": NSNull(),
            "metadata": [:]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-5",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.content.count == 2)

        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text at index 0")
            return
        }
        #expect(text.text == "Generated with container file.")

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("container_file_citation"),
                "container_id": .string("cntr_test"),
                "file_id": .string("file-container"),
                "filename": .string("data.csv"),
                "start_index": 0,
                "end_index": 10
            ])
        ]

        #expect(text.providerMetadata == [
            "openai": [
                "itemId": .string("msg_container"),
                "annotations": .array(expectedAnnotations)
            ]
        ])

        guard case .source(.document(_, let mediaType, let title, let filename, let providerMetadata)) = result.content[1] else {
            Issue.record("Expected document source at index 1")
            return
        }
        #expect(mediaType == "text/plain")
        #expect(title == "data.csv")
        #expect(filename == "data.csv")
        #expect(providerMetadata == [
            "openai": [
                "type": .string("container_file_citation"),
                "fileId": .string("file-container"),
                "containerId": .string("cntr_test")
            ]
        ])
    }

    // Port of openai-responses-language-model.test.ts: "should handle file_path annotations"
    @Test("should handle file_path annotations")
    func testShouldHandleFilePathAnnotations() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_file_path",
            "object": "response",
            "created_at": 1234567890,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "input": [],
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "model": "gpt-4o",
            "output": [
                [
                    "id": "msg_file_path",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Output written to file.",
                            "annotations": [
                                [
                                    "type": "file_path",
                                    "file_id": "file-path-123",
                                    "index": 0
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            "parallel_tool_calls": true,
            "previous_response_id": NSNull(),
            "reasoning": ["effort": NSNull(), "summary": NSNull()],
            "store": true,
            "temperature": 0,
            "text": ["format": ["type": "text"]],
            "tool_choice": "auto",
            "tools": [],
            "top_p": 1,
            "truncation": "disabled",
            "usage": [
                "input_tokens": 10,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens": 5,
                "output_tokens_details": ["reasoning_tokens": 0],
                "total_tokens": 15
            ],
            "user": NSNull(),
            "metadata": [:]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: samplePrompt))

        #expect(result.content.count == 2)

        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text at index 0")
            return
        }
        #expect(text.text == "Output written to file.")

        let expectedAnnotations: [JSONValue] = [
            .object([
                "type": .string("file_path"),
                "file_id": .string("file-path-123"),
                "index": 0
            ])
        ]

        #expect(text.providerMetadata == [
            "openai": [
                "itemId": .string("msg_file_path"),
                "annotations": .array(expectedAnnotations)
            ]
        ])

        guard case .source(.document(_, let mediaType, let title, let filename, let providerMetadata)) = result.content[1] else {
            Issue.record("Expected document source at index 1")
            return
        }
        #expect(mediaType == "application/octet-stream")
        #expect(title == "file-path-123")
        #expect(filename == "file-path-123")
        #expect(providerMetadata == [
            "openai": [
                "type": .string("file_path"),
                "fileId": .string("file-path-123"),
                "index": 0
            ]
        ])
    }

    // MARK: - Computer Use Tool Tests
    // Port of openai-responses-language-model.test.ts: "should handle computer use tool calls"

    @Test("should handle computer use tool calls")
    func testShouldHandleComputerUseToolCalls() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_computer_test",
            "object": "response",
            "created_at": 1_741_630_255,
            "status": "completed",
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "model": "gpt-4o-mini",
            "output": [
                [
                    "type": "computer_call",
                    "id": "computer_67cf2b3051e88190b006770db6fdb13d",
                    "status": "completed"
                ],
                [
                    "type": "message",
                    "id": "msg_computer_test",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "I've completed the computer task.",
                            "annotations": []
                        ]
                    ]
                ]
            ],
            "usage": ["input_tokens": 100, "output_tokens": 50]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { _ in
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIResponsesLanguageModel(
            modelId: "gpt-4o-mini",
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            LanguageModelV3Message.user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Use the computer to complete a task."))
                ],
                providerOptions: nil
            )
        ]

        let tools: [LanguageModelV3Tool] = [
            .providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "openai.computer_use",
                name: "computer_use",
                args: [:]
            ))
        ]

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: prompt, tools: tools)
        )

        // Verify content structure
        #expect(result.content.count == 3)

        // First: tool-call
        guard case .toolCall(let toolCall) = result.content[0] else {
            Issue.record("Expected tool-call at index 0")
            return
        }
        #expect(toolCall.toolCallId == "computer_67cf2b3051e88190b006770db6fdb13d")
        #expect(toolCall.toolName == "computer_use")
        #expect(toolCall.providerExecuted == true)
        #expect(toolCall.input == "")

        // Second: tool-result
        guard case .toolResult(let toolResult) = result.content[1] else {
            Issue.record("Expected tool-result at index 1")
            return
        }
        #expect(toolResult.toolCallId == "computer_67cf2b3051e88190b006770db6fdb13d")
        #expect(toolResult.toolName == "computer_use")
        #expect(toolResult.providerExecuted == true)

        // Verify result structure
        if case .object(let resultObj) = toolResult.result {
            #expect(resultObj["type"] == .string("computer_use_tool_result"))
            #expect(resultObj["status"] == .string("completed"))
        } else {
            Issue.record("Expected result to be an object")
        }

        // Third: text
        guard case .text(let textPart) = result.content[2] else {
            Issue.record("Expected text at index 2")
            return
        }
        #expect(textPart.text == "I've completed the computer task.")

        // Verify provider metadata
        if let metadata = textPart.providerMetadata,
           let openai = metadata["openai"],
           case .string(let itemId) = openai["itemId"] {
            #expect(itemId == "msg_computer_test")
        }
    }

}
