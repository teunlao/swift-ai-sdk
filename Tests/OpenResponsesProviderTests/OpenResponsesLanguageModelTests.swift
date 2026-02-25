import Foundation
import Testing
@testable import OpenResponsesProvider
import AISDKProvider
import AISDKProviderUtils

private let openResponsesTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private let openResponsesTestURL = "https://localhost:1234/v1/responses"

private actor RequestCapture {
    private var requests: [URLRequest] = []
    func store(_ request: URLRequest) { requests.append(request) }
    func first() -> URLRequest? { requests.first }
}

private func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
}

private func makeBasicOpenResponsesGenerateData() throws -> Data {
    let response: [String: Any] = [
        "id": "resp_test",
        "object": "response",
        "created_at": 1_768_900_049,
        "status": "completed",
        "incomplete_details": NSNull(),
        "model": "gemma-7b-it",
        "output": [
            [
                "id": "rs_1",
                "type": "reasoning",
                "content": [
                    ["type": "reasoning_text", "text": "reasoning content"]
                ]
            ],
            [
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "content": [
                    ["type": "output_text", "text": "text content"]
                ]
            ],
        ],
        "usage": [
            "input_tokens": 136,
            "output_tokens": 3677,
            "total_tokens": 3813,
            "input_tokens_details": ["cached_tokens": 0],
            "output_tokens_details": ["reasoning_tokens": 2456],
        ],
        "error": NSNull(),
    ]

    return try JSONSerialization.data(withJSONObject: response)
}

private func makeToolCallOpenResponsesGenerateData() throws -> Data {
    let response: [String: Any] = [
        "id": "resp_tool",
        "object": "response",
        "created_at": 1_769_005_553,
        "status": "completed",
        "incomplete_details": NSNull(),
        "model": "gemma-7b-it",
        "output": [
            [
                "id": "fc_1",
                "call_id": "call_123",
                "type": "function_call",
                "name": "weather",
                "arguments": "{\"location\":\"San Francisco\"}",
                "status": "completed",
            ],
        ],
        "usage": [
            "input_tokens": 10,
            "output_tokens": 2,
            "total_tokens": 12,
            "input_tokens_details": ["cached_tokens": 3],
            "output_tokens_details": ["reasoning_tokens": 0],
        ],
        "error": NSNull(),
    ]

    return try JSONSerialization.data(withJSONObject: response)
}

private func makeSSEData(from jsonLines: [String]) -> Data {
    let chunks = (jsonLines.map { "data: \($0)\n\n" } + ["data: [DONE]\n\n"]).joined()
    return Data(chunks.utf8)
}

@Suite("OpenResponsesLanguageModel", .serialized)
struct OpenResponsesLanguageModelTests {
    private func makeModel(fetch: @escaping FetchFunction) -> OpenResponsesLanguageModel {
        OpenResponsesLanguageModel(
            modelId: "gemma-7b-it",
            config: OpenResponsesConfig(
                provider: "lmstudio",
                url: openResponsesTestURL,
                headers: { [:] },
                fetch: fetch,
                generateId: generateID
            )
        )
    }

    @Test("doGenerate: sends correct basic request body and parses content/usage")
    func doGenerateBasic() async throws {
        let capture = RequestCapture()
        let responseData = try makeBasicOpenResponsesGenerateData()
        let url = try #require(URL(string: openResponsesTestURL))

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: openResponsesTestPrompt))

        let request = await capture.first()
        let bodyData = try #require(request?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        #expect(body["model"] == .string("gemma-7b-it"))
        #expect(body["instructions"] == nil)
        #expect(body["text"] == nil)

        guard case .array(let input)? = body["input"] else {
            Issue.record("Expected input array")
            return
        }
        #expect(input.count == 1)

        // Content
        #expect(result.content.count == 2)
        if case .reasoning(let r0) = result.content[0] {
            #expect(r0.text == "reasoning content")
        } else {
            Issue.record("Expected reasoning content first")
        }
        if case .text(let t1) = result.content[1] {
            #expect(t1.text == "text content")
        } else {
            Issue.record("Expected text content second")
        }

        // Usage
        #expect(result.usage.inputTokens.total == 136)
        #expect(result.usage.inputTokens.cacheRead == 0)
        #expect(result.usage.inputTokens.noCache == 136)
        #expect(result.usage.outputTokens.total == 3677)
        #expect(result.usage.outputTokens.reasoning == 2456)
        #expect(result.usage.outputTokens.text == 1221)
        #expect(result.usage.raw != nil)
    }

    @Test("doGenerate: request parameters map to snake_case + json_schema format")
    func doGenerateRequestParameters() async throws {
        let capture = RequestCapture()
        let responseData = try makeBasicOpenResponsesGenerateData()
        let url = try #require(URL(string: openResponsesTestURL))

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: openResponsesTestPrompt,
            maxOutputTokens: 100,
            temperature: 0.5,
            topP: 0.9,
            presencePenalty: 0.1,
            frequencyPenalty: 0.2,
            responseFormat: .json(
                schema: .object([
                    "type": .string("object"),
                    "properties": .object(["status": .object(["type": .string("string")])]),
                    "required": .array([.string("status")])
                ]),
                name: "response",
                description: "Example response schema"
            )
        ))

        let request = await capture.first()
        let bodyData = try #require(request?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        #expect(body["max_output_tokens"] == .number(100))
        #expect(body["temperature"] == .number(0.5))
        #expect(body["top_p"] == .number(0.9))
        #expect(body["presence_penalty"] == .number(0.1))
        #expect(body["frequency_penalty"] == .number(0.2))

        guard case .object(let text)? = body["text"],
              case .object(let format)? = text["format"] else {
            Issue.record("Expected text.format object")
            return
        }

        #expect(format["type"] == .string("json_schema"))
        #expect(format["name"] == .string("response"))
        #expect(format["description"] == .string("Example response schema"))
        #expect(format["strict"] == .bool(true))
        #expect(format["schema"] != nil)
    }

    @Test("doGenerate: tools map to tools[] with parameters + strict")
    func doGenerateTools() async throws {
        let capture = RequestCapture()
        let responseData = try makeBasicOpenResponsesGenerateData()
        let url = try #require(URL(string: openResponsesTestURL))

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: openResponsesTestPrompt,
            tools: [
                .function(.init(
                    name: "get_weather",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object(["location": .object(["type": .string("string")])]),
                        "required": .array([.string("location")])
                    ]),
                    description: "Get the current weather for a location"
                )),
                .function(.init(
                    name: "search",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object(["query": .object(["type": .string("string")])]),
                        "required": .array([.string("query")])
                    ]),
                    description: "Search for information",
                    strict: true
                )),
            ]
        ))

        let request = await capture.first()
        let bodyData = try #require(request?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        guard case .array(let tools)? = body["tools"] else {
            Issue.record("Expected tools array")
            return
        }
        #expect(tools.count == 2)

        guard case .object(let tool0) = tools[0] else { Issue.record("Expected tool object"); return }
        #expect(tool0["type"] == .string("function"))
        #expect(tool0["name"] == .string("get_weather"))
        #expect(tool0["description"] == .string("Get the current weather for a location"))
        #expect(tool0["parameters"] != nil)
        #expect(tool0["strict"] == nil)

        guard case .object(let tool1) = tools[1] else { Issue.record("Expected tool object"); return }
        #expect(tool1["name"] == .string("search"))
        #expect(tool1["strict"] == .bool(true))
    }

    @Test("doGenerate: tool_choice required and specific tool map correctly")
    func doGenerateToolChoice() async throws {
        let capture = RequestCapture()
        let responseData = try makeBasicOpenResponsesGenerateData()
        let url = try #require(URL(string: openResponsesTestURL))

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: openResponsesTestPrompt,
            toolChoice: .required
        ))

        var request = await capture.first()
        var bodyData = try #require(request?.httpBody)
        var body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)
        #expect(body["tool_choice"] == .string("required"))

        // Specific tool
        let capture2 = RequestCapture()
        let fetch2: FetchFunction = { req in
            await capture2.store(req)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }
        let model2 = makeModel(fetch: fetch2)
        _ = try await model2.doGenerate(options: .init(
            prompt: openResponsesTestPrompt,
            toolChoice: .tool(toolName: "get_weather")
        ))

        request = await capture2.first()
        bodyData = try #require(request?.httpBody)
        body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        guard case .object(let toolChoice)? = body["tool_choice"] else {
            Issue.record("Expected tool_choice object")
            return
        }
        #expect(toolChoice["type"] == .string("function"))
        #expect(toolChoice["name"] == .string("get_weather"))
    }

    @Test("doGenerate: system messages map to instructions")
    func doGenerateSystemInstructions() async throws {
        let capture = RequestCapture()
        let responseData = try makeBasicOpenResponsesGenerateData()
        let url = try #require(URL(string: openResponsesTestURL))

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "You are a helpful assistant.", providerOptions: nil),
                .system(content: "Always be concise.", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ]
        ))

        let request = await capture.first()
        let bodyData = try #require(request?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)
        #expect(body["instructions"] == .string("You are a helpful assistant.\nAlways be concise."))
    }

    @Test("doGenerate: multi-turn tool conversation prompt maps to input items")
    func doGenerateMultiTurnToolConversation() async throws {
        let capture = RequestCapture()
        let responseData = try makeBasicOpenResponsesGenerateData()
        let url = try #require(URL(string: openResponsesTestURL))

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = makeModel(fetch: fetch)
        let toolConversationPrompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "What is the weather in Tokyo?"))], providerOptions: nil),
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "call_weather_123",
                    toolName: "get_weather",
                    input: .object(["location": .string("Tokyo")])
                ))
            ], providerOptions: nil),
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call_weather_123",
                    toolName: "get_weather",
                    output: .json(value: .object([
                        "temperature": .number(22),
                        "condition": .string("sunny"),
                        "humidity": .number(65),
                    ]))
                ))
            ], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: toolConversationPrompt,
            tools: [
                .function(.init(
                    name: "get_weather",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object(["location": .object(["type": .string("string")])]),
                        "required": .array([.string("location")])
                    ]),
                    description: "Get the current weather for a location"
                ))
            ]
        ))

        let request = await capture.first()
        let bodyData = try #require(request?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        guard case .array(let input)? = body["input"] else {
            Issue.record("Expected input array")
            return
        }

        #expect(input.count == 3)
        guard case .object(let user) = input[0] else { Issue.record("Expected user object"); return }
        guard case .object(let toolCall) = input[1] else { Issue.record("Expected tool call object"); return }
        guard case .object(let toolResult) = input[2] else { Issue.record("Expected tool result object"); return }
        #expect(user["role"] == .string("user"))
        #expect(toolCall["type"] == .string("function_call"))
        #expect(toolResult["type"] == .string("function_call_output"))
    }

    @Test("doGenerate: parses tool-call response + tool-calls finish reason")
    func doGenerateToolCallResponse() async throws {
        let capture = RequestCapture()
        let responseData = try makeToolCallOpenResponsesGenerateData()
        let url = try #require(URL(string: openResponsesTestURL))

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(
            prompt: openResponsesTestPrompt,
            toolChoice: .required
        ))

        #expect(result.content.count == 1)
        if case .toolCall(let toolCall) = result.content[0] {
            #expect(toolCall.toolName == "weather")
            #expect(toolCall.toolCallId == "call_123")
            #expect(toolCall.input == "{\"location\":\"San Francisco\"}")
        } else {
            Issue.record("Expected tool-call content")
        }

        #expect(result.finishReason.unified == .toolCalls)
        #expect(result.finishReason.raw == nil)
        #expect(result.usage.inputTokens.cacheRead == 3)
        #expect(result.usage.inputTokens.noCache == 7)
    }

    @Test("doStream: streams text parts and finishes with stop")
    func doStreamBasic() async throws {
        let responseData = makeSSEData(from: [
            "{\"type\":\"response.output_item.added\",\"item\":{\"id\":\"msg_1\",\"type\":\"message\"}}",
            "{\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"Hi\"}",
            "{\"type\":\"response.output_item.done\",\"item\":{\"id\":\"msg_1\",\"type\":\"message\"}}",
            "{\"type\":\"response.completed\",\"response\":{\"incomplete_details\":null,\"usage\":{\"input_tokens\":2,\"output_tokens\":3,\"input_tokens_details\":{\"cached_tokens\":1},\"output_tokens_details\":{\"reasoning_tokens\":0}}}}",
        ])

        let url = try #require(URL(string: openResponsesTestURL))
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url, headers: ["Content-Type": "text/event-stream"]))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: openResponsesTestPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await p in result.stream { parts.append(p) }

        #expect(parts.count >= 5)
        if case .streamStart = parts.first {
            // ok
        } else {
            Issue.record("Expected stream-start first")
        }

        #expect(parts.contains { if case .textDelta(_, let delta, _) = $0 { return delta == "Hi" } else { return false } })

        guard let finish = parts.last, case .finish(let finishReason, let usage, _) = finish else {
            Issue.record("Expected finish last")
            return
        }
        #expect(finishReason.unified == .stop)
        #expect(usage.inputTokens.total == 2)
        #expect(usage.inputTokens.cacheRead == 1)
        #expect(usage.inputTokens.noCache == 1)
    }

    @Test("doStream: streams reasoning + tool-call and finishes with tool-calls")
    func doStreamReasoningWithToolCall() async throws {
        let responseData = makeSSEData(from: [
            "{\"type\":\"response.output_item.added\",\"item\":{\"id\":\"rs_1\",\"type\":\"reasoning\"}}",
            "{\"type\":\"response.reasoning_text.delta\",\"item_id\":\"rs_1\",\"delta\":\"reason\"}",
            "{\"type\":\"response.output_item.done\",\"item\":{\"id\":\"rs_1\",\"type\":\"reasoning\"}}",
            "{\"type\":\"response.output_item.added\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_123\",\"name\":\"weather\",\"arguments\":\"\"}}",
            "{\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"fc_1\",\"delta\":\"{\\\"location\\\":\\\"San Francisco\\\"}\"}",
            "{\"type\":\"response.output_item.done\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_123\",\"name\":\"weather\",\"arguments\":\"{\\\"location\\\":\\\"San Francisco\\\"}\"}}",
            "{\"type\":\"response.completed\",\"response\":{\"incomplete_details\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":2,\"input_tokens_details\":{\"cached_tokens\":3},\"output_tokens_details\":{\"reasoning_tokens\":0}}}}",
        ])

        let url = try #require(URL(string: openResponsesTestURL))
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url, headers: ["Content-Type": "text/event-stream"]))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: openResponsesTestPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await p in result.stream { parts.append(p) }

        #expect(parts.contains { if case .reasoningDelta(_, let delta, _) = $0 { return delta == "reason" } else { return false } })
        #expect(parts.contains { if case .toolCall(let call) = $0 { return call.toolName == "weather" } else { return false } })

        guard let finish = parts.last, case .finish(let finishReason, let usage, _) = finish else {
            Issue.record("Expected finish last")
            return
        }
        #expect(finishReason.unified == .toolCalls)
        #expect(usage.inputTokens.cacheRead == 3)
        #expect(usage.inputTokens.noCache == 7)
    }
}
