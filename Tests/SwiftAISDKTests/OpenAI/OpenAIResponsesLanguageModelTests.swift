import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

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
    private func makeConfig(fetch: @escaping FetchFunction) -> OpenAIConfig {
        let generator = SequentialIdGenerator()
        return OpenAIConfig(
            provider: "openai.responses",
            url: { options in "https://api.openai.com/v1\(options.path)" },
            headers: { [:] },
            fetch: fetch,
            generateId: { generator.next() },
            fileIdPrefixes: ["file-"]
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
            #expect(format["strict"] as? Bool == false)
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
            if case .toolInputStart(let id, let name, _, let executed) = part {
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
            if case .toolInputStart(let id, let name, _, let executed) = part {
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

}
