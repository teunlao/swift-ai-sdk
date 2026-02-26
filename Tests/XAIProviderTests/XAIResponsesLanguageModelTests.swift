import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import XAIProvider

/**
 Tests for XAIResponsesLanguageModel.

 Port of `@ai-sdk/xai/src/responses/xai-responses-language-model.test.ts`.
 */
@Suite("XAIResponsesLanguageModel")
struct XAIResponsesLanguageModelTests {
    private static let testPrompt: LanguageModelV3Prompt = [
        .user(content: [.text(.init(text: "hello"))], providerOptions: nil)
    ]

    private final class IDGenerator: @unchecked Sendable {
        private var nextValue: Int = 0
        private let lock = NSLock()

        func next() -> String {
            lock.lock()
            defer { lock.unlock() }
            defer { nextValue += 1 }
            return "id-\(nextValue)"
        }
    }

    private actor RequestCapture {
        private var request: URLRequest?
        private var body: JSONValue?

        func store(request: URLRequest, body: JSONValue?) {
            self.request = request
            self.body = body
        }

        func snapshot() -> (request: URLRequest?, body: JSONValue?) {
            (request: request, body: body)
        }
    }

    private static func makeHTTPResponse(
        url: String = "https://api.x.ai/v1/responses",
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private static func makeStream(from events: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data(event.utf8))
            }
            continuation.finish()
        }
    }

    private static func sseEvents(_ payloads: [String]) -> [String] {
        payloads.map { "data: \($0)\n\n" } + ["data: [DONE]\n\n"]
    }

    private static func collect(_ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream {
            parts.append(part)
        }
        return parts
    }

    private static func makeModel(
        modelId: String = "grok-4-fast",
        fetch: @escaping FetchFunction,
        generateId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) -> XAIResponsesLanguageModel {
        XAIResponsesLanguageModel(
            modelId: XAIResponsesModelId(rawValue: modelId),
            config: XAIResponsesLanguageModel.Config(
                provider: "xai.responses",
                baseURL: "https://api.x.ai/v1",
                headers: { ["Authorization": "Bearer test-key"] },
                generateId: generateId,
                fetch: fetch
            )
        )
    }

    // MARK: - doGenerate

    @Test("generates text content")
    func doGenerateBasicText() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "created_at": 1_700_000_000,
            "status": "completed",
            "model": "grok-4-fast",
            "output": [[
                "type": "message",
                "id": "msg_123",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "hello world",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 10,
                "output_tokens": 5,
                "total_tokens": 15
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        })

        let result = try await model.doGenerate(options: .init(prompt: Self.testPrompt))

        #expect(result.content.count == 1)
        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.text == "hello world")
    }

    @Test("extracts usage correctly")
    func doGenerateUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [],
            "usage": [
                "input_tokens": 345,
                "output_tokens": 538,
                "total_tokens": 883,
                "output_tokens_details": [
                    "reasoning_tokens": 123
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        })

        let result = try await model.doGenerate(options: .init(prompt: Self.testPrompt))

        #expect(result.usage.inputTokens.total == 345)
        #expect(result.usage.inputTokens.noCache == 345)
        #expect(result.usage.inputTokens.cacheRead == 0)
        #expect(result.usage.outputTokens.total == 538)
        #expect(result.usage.outputTokens.reasoning == 123)
        #expect(result.usage.outputTokens.text == 415)
    }

    @Test("extracts finish reason from status")
    func doGenerateFinishReason() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [],
            "usage": ["input_tokens": 10, "output_tokens": 5]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        })

        let result = try await model.doGenerate(options: .init(prompt: Self.testPrompt))

        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "completed")
    }

    @Test("extracts reasoning with encrypted content when present")
    func doGenerateReasoningEncryptedContent() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [
                [
                    "type": "reasoning",
                    "id": "rs_456",
                    "status": "completed",
                    "summary": [[
                        "type": "summary_text",
                        "text": "First, analyze the question carefully."
                    ]],
                    "encrypted_content": "abc123encryptedcontent"
                ],
                [
                    "type": "message",
                    "id": "msg_123",
                    "status": "completed",
                    "role": "assistant",
                    "content": [[
                        "type": "output_text",
                        "text": "The answer is 42.",
                        "annotations": []
                    ]]
                ]
            ],
            "usage": [
                "input_tokens": 10,
                "output_tokens": 20,
                "output_tokens_details": ["reasoning_tokens": 15]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        })

        let result = try await model.doGenerate(options: .init(prompt: Self.testPrompt))

        #expect(result.content.count == 2)
        guard case .reasoning(let reasoning) = result.content[0] else {
            Issue.record("Expected reasoning content")
            return
        }
        #expect(reasoning.text == "First, analyze the question carefully.")
        #expect(reasoning.providerMetadata?["xai"]?["itemId"] == .string("rs_456"))
        #expect(reasoning.providerMetadata?["xai"]?["reasoningEncryptedContent"] == .string("abc123encryptedcontent"))

        guard case .text(let text) = result.content[1] else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.text == "The answer is 42.")
    }

    @Test("sends model id and settings")
    func doGenerateSendsModelAndSettings() async throws {
        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [],
            "usage": ["input_tokens": 10, "output_tokens": 5]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let fetch: FetchFunction = { request in
            let body: JSONValue?
            if let raw = request.httpBody {
                body = try? JSONDecoder().decode(JSONValue.self, from: raw)
            } else {
                body = nil
            }
            await capture.store(request: request, body: body)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = Self.makeModel(modelId: "grok-4-fast", fetch: fetch)

        let prompt: LanguageModelV3Prompt = [
            .system(content: "you are helpful", providerOptions: nil),
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            maxOutputTokens: 100,
            temperature: 0.5,
            topP: 0.9
        ))

        let snapshot = await capture.snapshot()
        guard let body = snapshot.body else {
            Issue.record("Expected request body to be captured")
            return
        }

        guard case .object(let dict) = body else {
            Issue.record("Expected request body to be an object")
            return
        }

        #expect(dict["model"] == .string("grok-4-fast"))
        #expect(dict["max_output_tokens"] == .number(100))
        #expect(dict["temperature"] == .number(0.5))
        #expect(dict["top_p"] == .number(0.9))

        guard case .array(let input)? = dict["input"] else {
            Issue.record("Expected input array")
            return
        }
        #expect(input.count == 2)
    }

    @Test("provider options reasoningEffort/store/include/previousResponseId")
    func doGenerateProviderOptions() async throws {
        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [],
            "usage": ["input_tokens": 10, "output_tokens": 5]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let fetch: FetchFunction = { request in
            let body: JSONValue? = request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            await capture.store(request: request, body: body)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = Self.makeModel(fetch: fetch)

        let options = XAILanguageModelResponsesOptions(
            reasoningEffort: .high,
            store: false,
            previousResponseId: "resp_456",
            include: ["file_search_call.results"]
        )

        _ = try await model.doGenerate(options: .init(
            prompt: Self.testPrompt,
            providerOptions: ["xai": [
                "reasoningEffort": .string(options.reasoningEffort!.rawValue),
                "store": .bool(false),
                "previousResponseId": .string("resp_456"),
                "include": .array([.string("file_search_call.results")])
            ]]
        ))

        let snapshot = await capture.snapshot()
        guard let body = snapshot.body else {
            Issue.record("Expected request body")
            return
        }

        guard case .object(let dict) = body else {
            Issue.record("Expected request body to be an object")
            return
        }

        #expect(dict["store"] == .bool(false))
        #expect(dict["previous_response_id"] == .string("resp_456"))

        // include should contain both file_search_call.results and reasoning.encrypted_content when store=false
        guard case .array(let include)? = dict["include"] else {
            Issue.record("Expected include array")
            return
        }
        #expect(include.contains(.string("file_search_call.results")))
        #expect(include.contains(.string("reasoning.encrypted_content")))

        #expect(dict["reasoning"] == .object(["effort": .string("high")]))
    }

    @Test("warns about unsupported stopSequences")
    func doGenerateStopSequencesWarning() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [],
            "usage": ["input_tokens": 10, "output_tokens": 5]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        })

        let result = try await model.doGenerate(options: .init(
            prompt: Self.testPrompt,
            stopSequences: ["\n\n", "STOP"]
        ))

        #expect(result.warnings == [
            .unsupported(feature: "stopSequences", details: nil)
        ])
    }

    @Test("responseFormat json schema and json object")
    func doGenerateResponseFormat() async throws {
        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [],
            "usage": ["input_tokens": 10, "output_tokens": 5]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let fetch: FetchFunction = { request in
            let body: JSONValue? = request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            await capture.store(request: request, body: body)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = Self.makeModel(fetch: fetch)

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "ingredients": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ])
            ]),
            "required": .array([.string("name"), .string("ingredients")]),
            "additionalProperties": .bool(false)
        ])

        _ = try await model.doGenerate(options: .init(
            prompt: Self.testPrompt,
            responseFormat: .json(schema: schema, name: "recipe", description: "A recipe object")
        ))

        let snapshot1 = await capture.snapshot()
        guard let body1 = snapshot1.body else {
            Issue.record("Expected request body")
            return
        }

        guard case .object(let dict1) = body1,
              case .object(let text)? = dict1["text"],
              case .object(let format)? = text["format"] else {
            Issue.record("Expected text.format payload")
            return
        }
        #expect(format["type"] == .string("json_schema"))
        #expect(format["strict"] == .bool(true))
        #expect(format["name"] == .string("recipe"))
        #expect(format["description"] == .string("A recipe object"))
        #expect(format["schema"] == schema)

        _ = try await model.doGenerate(options: .init(
            prompt: Self.testPrompt,
            responseFormat: .json(schema: nil, name: nil, description: nil)
        ))

        let snapshot2 = await capture.snapshot()
        guard let body2 = snapshot2.body else {
            Issue.record("Expected request body")
            return
        }
        guard case .object(let dict2) = body2,
              case .object(let text2)? = dict2["text"],
              case .object(let format2)? = text2["format"] else {
            Issue.record("Expected text.format payload")
            return
        }
        #expect(format2["type"] == .string("json_object"))
    }

    @Test("file_search tool call and result with providerExecuted true")
    func doGenerateFileSearchToolCallAndResult() async throws {
        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [
                [
                    "type": "file_search_call",
                    "id": "fs_123",
                    "status": "completed",
                    "queries": ["AI safety research"],
                    "results": [[
                        "file_id": "file_abc123",
                        "filename": "ai-safety-paper.pdf",
                        "score": 0.95,
                        "text": "Recent advances..."
                    ]]
                ],
                [
                    "type": "message",
                    "id": "msg_123",
                    "status": "completed",
                    "role": "assistant",
                    "content": [[
                        "type": "output_text",
                        "text": "Based on the documents...",
                        "annotations": []
                    ]]
                ]
            ],
            "usage": ["input_tokens": 100, "output_tokens": 20]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        })

        let tools: [LanguageModelV3Tool] = [
            .provider(.init(
                id: "xai.file_search",
                name: "file_search",
                args: ["vectorStoreIds": .array([.string("collection_test123")])]
            ))
        ]

        let result = try await model.doGenerate(options: .init(prompt: Self.testPrompt, tools: tools))

        #expect(result.content.count == 3)
        guard case .toolCall(let call) = result.content[0] else {
            Issue.record("Expected tool-call")
            return
        }
        #expect(call.toolCallId == "fs_123")
        #expect(call.toolName == "file_search")
        #expect(call.input == "")
        #expect(call.providerExecuted == true)

        guard case .toolResult(let toolResult) = result.content[1] else {
            Issue.record("Expected tool-result")
            return
        }
        #expect(toolResult.toolCallId == "fs_123")
        #expect(toolResult.toolName == "file_search")
        if case .object(let dict) = toolResult.result {
            #expect(dict["queries"] != nil)
        } else {
            Issue.record("Expected tool result payload to be an object")
        }

        guard case .text = result.content[2] else {
            Issue.record("Expected text")
            return
        }
    }

    @Test("extracts citations from annotations")
    func doGenerateCitations() async throws {
        let ids = IDGenerator()

        let responseJSON: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": "grok-4-fast",
            "output": [[
                "type": "message",
                "id": "msg_123",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "based on research",
                    "annotations": [
                        ["type": "url_citation", "url": "https://example.com", "title": "example title"],
                        ["type": "url_citation", "url": "https://test.com"]
                    ]
                ]]
            ]],
            "usage": ["input_tokens": 10, "output_tokens": 5]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = Self.makeHTTPResponse()

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }, generateId: { ids.next() })

        let result = try await model.doGenerate(options: .init(prompt: Self.testPrompt))

        #expect(result.content.count == 3)
        guard case .source(let source1) = result.content[1],
              case .url(let id1, let url1, let title1, _) = source1 else {
            Issue.record("Expected first source")
            return
        }
        #expect(id1 == "id-0")
        #expect(url1 == "https://example.com")
        #expect(title1 == "example title")

        guard case .source(let source2) = result.content[2],
              case .url(let id2, let url2, let title2, _) = source2 else {
            Issue.record("Expected second source")
            return
        }
        #expect(id2 == "id-1")
        #expect(url2 == "https://test.com")
        #expect(title2 == "https://test.com")
    }

    // MARK: - doStream

    @Test("streams tool call arguments for function tools")
    func doStreamFunctionCallArguments() async throws {
        let chunks = [
            #"{"type":"response.created","response":{"id":"resp_123","object":"response","model":"grok-4-fast","status":"in_progress","output":[]}}"#,
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_123","call_id":"call_123","name":"weather","arguments":"","status":"in_progress"}}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_123","output_index":0,"delta":"{\"location\""}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_123","output_index":0,"delta":":\"sf\"}"}"#,
            #"{"type":"response.function_call_arguments.done","item_id":"fc_123","output_index":0,"arguments":"{\"location\":\"sf\"}"}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_123","call_id":"call_123","name":"weather","arguments":"{\"location\":\"sf\"}","status":"completed"}}"#,
            #"{"type":"response.done","response":{"id":"resp_123","object":"response","status":"completed","output":[],"usage":{"input_tokens":10,"output_tokens":5}}}"#
        ]

        let events = Self.sseEvents(chunks)
        let httpResponse = Self.makeHTTPResponse(headers: ["Content-Type": "text/event-stream"])

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .stream(Self.makeStream(from: events)), urlResponse: httpResponse)
        })

        let toolSchema: JSONValue = .object(["type": .string("object"), "properties": .object([:])])
        let tools: [LanguageModelV3Tool] = [
            .function(.init(name: "weather", inputSchema: toolSchema, description: "get weather"))
        ]

        let result = try await model.doStream(options: .init(prompt: Self.testPrompt, tools: tools))
        let parts = try await Self.collect(result.stream)

        #expect(parts.contains(where: { if case .toolInputStart(let id, let toolName, _, _, _, _) = $0 { return id == "call_123" && toolName == "weather" } else { return false } }))
        #expect(parts.contains(where: { if case .toolInputDelta(let id, let delta, _) = $0 { return id == "call_123" && delta == "{\"location\"" } else { return false } }))
        #expect(parts.contains(where: { if case .toolInputDelta(let id, let delta, _) = $0 { return id == "call_123" && delta == ":\"sf\"}" } else { return false } }))
        #expect(parts.contains(where: { if case .toolInputEnd(let id, _) = $0 { return id == "call_123" } else { return false } }))
        #expect(parts.contains(where: { if case .toolCall(let call) = $0 { return call.toolCallId == "call_123" && call.toolName == "weather" && call.input == "{\"location\":\"sf\"}" } else { return false } }))
    }

    @Test("streams file_search tool call and result")
    func doStreamFileSearchToolCallAndResult() async throws {
        let chunks = [
            #"{"type":"response.created","response":{"id":"resp_123","object":"response","model":"grok-4-fast","status":"in_progress","output":[]}}"#,
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"file_search_call","id":"fs_stream_123","status":"in_progress","queries":["search query"],"results":null}}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"file_search_call","id":"fs_stream_123","status":"completed","queries":["search query"],"results":[{"file_id":"file_abc","filename":"doc.txt","score":0.9,"text":"Found text content"}]}}"#,
            #"{"type":"response.done","response":{"id":"resp_123","object":"response","status":"completed","output":[],"usage":{"input_tokens":10,"output_tokens":5}}}"#
        ]

        let events = Self.sseEvents(chunks)
        let httpResponse = Self.makeHTTPResponse(headers: ["Content-Type": "text/event-stream"])

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .stream(Self.makeStream(from: events)), urlResponse: httpResponse)
        })

        let tools: [LanguageModelV3Tool] = [
            .provider(.init(
                id: "xai.file_search",
                name: "file_search",
                args: ["vectorStoreIds": .array([.string("collection_123")])]
            ))
        ]

        let result = try await model.doStream(options: .init(prompt: Self.testPrompt, tools: tools))
        let parts = try await Self.collect(result.stream)

        #expect(parts.contains(where: { if case .toolInputStart(let id, let toolName, _, _, _, _) = $0 { return id == "fs_stream_123" && toolName == "file_search" } else { return false } }))
        #expect(parts.contains(where: { if case .toolInputDelta(let id, let delta, _) = $0 { return id == "fs_stream_123" && delta == "" } else { return false } }))
        #expect(parts.contains(where: { if case .toolInputEnd(let id, _) = $0 { return id == "fs_stream_123" } else { return false } }))
        #expect(parts.contains(where: { if case .toolCall(let call) = $0 { return call.toolCallId == "fs_stream_123" && call.toolName == "file_search" && call.providerExecuted == true } else { return false } }))
        #expect(parts.contains(where: { if case .toolResult(let result) = $0 { return result.toolCallId == "fs_stream_123" && result.toolName == "file_search" } else { return false } }))
    }

    @Test("does not emit duplicate text-delta from output_item.done after streaming")
    func doStreamNoDuplicateTextDelta() async throws {
        let chunks = [
            #"{"type":"response.created","response":{"id":"resp_123","object":"response","model":"grok-4-fast","created_at":1700000000,"status":"in_progress","output":[]}}"#,
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_123","status":"in_progress","role":"assistant","content":[]}}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_123","output_index":0,"content_index":0,"delta":"Hello"}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_123","output_index":0,"content_index":0,"delta":" "} "#,
            #"{"type":"response.output_text.delta","item_id":"msg_123","output_index":0,"content_index":0,"delta":"world"}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_123","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello world","annotations":[]}]}}"#,
            #"{"type":"response.done","response":{"id":"resp_123","object":"response","status":"completed","output":[],"usage":{"input_tokens":10,"output_tokens":5}}}"#
        ]

        // Fix accidental extra whitespace in the second delta chunk
        let fixed = chunks.map { $0.trimmingCharacters(in: .whitespaces) }

        let events = Self.sseEvents(fixed)
        let httpResponse = Self.makeHTTPResponse(headers: ["Content-Type": "text/event-stream"])

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .stream(Self.makeStream(from: events)), urlResponse: httpResponse)
        })

        let result = try await model.doStream(options: .init(prompt: Self.testPrompt))
        let parts = try await Self.collect(result.stream)

        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }

        #expect(textDeltas == ["Hello", " ", "world"])
        #expect(textDeltas.contains("Hello world") == false)
    }

    @Test("includes encrypted content in reasoning-end providerMetadata")
    func doStreamReasoningEncryptedContentProviderMetadata() async throws {
        let chunks = [
            #"{"type":"response.created","response":{"id":"resp_123","object":"response","model":"grok-4-fast","output":[]}}"#,
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_456","status":"in_progress","summary":[]}}"#,
            #"{"type":"response.reasoning_summary_part.added","item_id":"rs_456","output_index":0,"summary_index":0,"part":{"type":"summary_text","text":""}}"#,
            #"{"type":"response.reasoning_summary_text.delta","item_id":"rs_456","output_index":0,"summary_index":0,"delta":"Analyzing..."}"#,
            #"{"type":"response.reasoning_summary_text.done","item_id":"rs_456","output_index":0,"summary_index":0,"text":"Analyzing..."}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_456","status":"completed","summary":[{"type":"summary_text","text":"Analyzing..."}],"encrypted_content":"encrypted_data_abc123"}}"#,
            #"{"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"msg_789","role":"assistant","status":"in_progress","content":[]}}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_789","output_index":1,"content_index":0,"delta":"Result."}"#,
            #"{"type":"response.done","response":{"id":"resp_123","object":"response","model":"grok-4-fast","status":"completed","output":[],"usage":{"input_tokens":10,"output_tokens":20}}}"#
        ]

        let events = Self.sseEvents(chunks)
        let httpResponse = Self.makeHTTPResponse(headers: ["Content-Type": "text/event-stream"])

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .stream(Self.makeStream(from: events)), urlResponse: httpResponse)
        })

        let result = try await model.doStream(options: .init(prompt: Self.testPrompt))
        let parts = try await Self.collect(result.stream)

        let reasoningEnd = parts.first { part in
            if case .reasoningEnd = part { return true }
            return false
        }

        guard let reasoningEnd, case .reasoningEnd(let id, let metadata) = reasoningEnd else {
            Issue.record("Expected reasoning-end part")
            return
        }

        #expect(id == "reasoning-rs_456")
        #expect(metadata?["xai"]?["itemId"] == .string("rs_456"))
        #expect(metadata?["xai"]?["reasoningEncryptedContent"] == .string("encrypted_data_abc123"))
    }

    @Test("streams citations as sources")
    func doStreamCitations() async throws {
        let ids = IDGenerator()
        let chunks = [
            #"{"type":"response.created","response":{"id":"resp_123","object":"response","model":"grok-4-fast","status":"in_progress","output":[]}}"#,
            #"{"type":"response.output_text.annotation.added","item_id":"msg_123","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"url_citation","url":"https://example.com","title":"example"}}"#,
            #"{"type":"response.done","response":{"id":"resp_123","object":"response","status":"completed","output":[],"usage":{"input_tokens":10,"output_tokens":5}}}"#
        ]

        let events = Self.sseEvents(chunks)
        let httpResponse = Self.makeHTTPResponse(headers: ["Content-Type": "text/event-stream"])

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .stream(Self.makeStream(from: events)), urlResponse: httpResponse)
        }, generateId: { ids.next() })

        let result = try await model.doStream(options: .init(prompt: Self.testPrompt))
        let parts = try await Self.collect(result.stream)

        let source = parts.first { part in
            if case .source = part { return true }
            return false
        }

        guard let source,
              case .source(let src) = source,
              case .url(let id, let url, let title, _) = src else {
            Issue.record("Expected url source")
            return
        }

        #expect(id == "id-0")
        #expect(url == "https://example.com")
        #expect(title == "example")
    }

    @Test("handles missing usage in streaming response")
    func doStreamMissingUsageDefaults() async throws {
        let chunks = [
            #"{"type":"response.created","response":{"id":"resp_123","object":"response","model":"grok-4-fast","created_at":1700000000,"status":"in_progress","output":[]}}"#,
            #"{"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"Hello"}"#,
            #"{"type":"response.completed","response":{"id":"resp_123","object":"response","model":"grok-4-fast","created_at":1700000000,"status":"completed","output":[{"type":"message","id":"msg_001","role":"assistant","status":"completed","content":[{"type":"output_text","text":"Hello"}]}]}}"#
        ]

        let events = Self.sseEvents(chunks)
        let httpResponse = Self.makeHTTPResponse(headers: ["Content-Type": "text/event-stream"])

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .stream(Self.makeStream(from: events)), urlResponse: httpResponse)
        })

        let result = try await model.doStream(options: .init(prompt: Self.testPrompt))
        let parts = try await Self.collect(result.stream)

        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
              case .finish(let finishReason, let usage, _) = finish else {
            Issue.record("Expected finish part")
            return
        }

        #expect(finishReason.unified == .stop)
        #expect(finishReason.raw == "completed")
        #expect(usage.inputTokens.total == 0)
        #expect(usage.inputTokens.noCache == 0)
        #expect(usage.inputTokens.cacheRead == 0)
        #expect(usage.inputTokens.cacheWrite == 0)
        #expect(usage.outputTokens.total == 0)
        #expect(usage.outputTokens.text == 0)
        #expect(usage.outputTokens.reasoning == 0)
    }

    @Test("accepts response.created/in_progress with usage: null")
    func doStreamSchemaValidationUsageNull() async throws {
        let chunks = [
            #"{"type":"response.created","response":{"id":"resp_123","object":"response","model":"grok-4-fast","created_at":1700000000,"status":"in_progress","output":[],"usage":null}}"#,
            #"{"type":"response.in_progress","response":{"id":"resp_123","object":"response","model":"grok-4-fast","created_at":1700000000,"status":"in_progress","output":[],"usage":null}}"#,
            #"{"type":"response.output_item.added","item":{"id":"msg_001","type":"message","role":"assistant","content":[],"status":"in_progress"},"output_index":0}"#,
            #"{"type":"response.content_part.added","item_id":"msg_001","output_index":0,"content_index":0,"part":{"type":"output_text","text":""}}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_001","output_index":0,"content_index":0,"delta":"Hello"}"#,
            #"{"type":"response.completed","response":{"id":"resp_123","object":"response","model":"grok-4-fast","created_at":1700000000,"status":"completed","output":[{"id":"msg_001","type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello"}],"status":"completed"}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}}"#
        ]

        let events = Self.sseEvents(chunks)
        let httpResponse = Self.makeHTTPResponse(headers: ["Content-Type": "text/event-stream"])

        let model = Self.makeModel(fetch: { _ in
            FetchResponse(body: .stream(Self.makeStream(from: events)), urlResponse: httpResponse)
        })

        let result = try await model.doStream(options: .init(prompt: Self.testPrompt))
        let parts = try await Self.collect(result.stream)

        #expect(parts.contains(where: { if case .textDelta(_, let delta, _) = $0 { return delta == "Hello" } else { return false } }))
        #expect(parts.contains(where: { if case .finish = $0 { return true } else { return false } }))
    }
}
