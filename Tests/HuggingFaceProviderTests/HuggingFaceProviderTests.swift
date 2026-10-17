import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import HuggingFaceProvider

@Suite("Hugging Face Responses V4")
struct HuggingFaceProviderTests {
    @Test("requests carry Responses prompts, native options, tools and API headers")
    func requestContract() async throws {
        let schema: JSONValue = ["type": "object"]
        let fetch: FetchFunction = { request in
            #expect(request.url?.absoluteString == "https://proxy.example/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer custom-key")
            #expect(request.value(forHTTPHeaderField: "X-Account") == "account")
            #expect(request.value(forHTTPHeaderField: "X-Request") == "request")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-huggingface/") == true)
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object([
                "model": "custom-model", "stream": false,
                "temperature": 0.4, "top_p": 0.8, "max_output_tokens": 128,
                "metadata": ["tenant": "one"], "instructions": "Be precise",
                "reasoning": ["effort": "custom-effort"],
                "text": ["format": ["type": "json_schema", "name": "answer", "description": "A result", "strict": true, "schema": schema]],
                "tools": [["type": "function", "name": "lookup", "description": "Lookup", "parameters": schema]],
                "tool_choice": ["type": "function", "function": ["name": "lookup"]],
                "input": [
                    ["role": "system", "content": "Policy"],
                    ["role": "user", "content": [
                        ["type": "input_text", "text": "Question"],
                        ["type": "input_image", "image_url": "data:image/png;base64,iVBORw0KGgo="],
                        ["type": "input_image", "image_url": "https://media.example/image.png"]
                    ]],
                    ["role": "assistant", "content": [["type": "output_text", "text": "Thinking"]]],
                    ["role": "assistant", "content": [["type": "output_text", "text": "Answer"]]]
                ]
            ]))
            return try jsonResponse(request, responseValue())
        }
        let model = createHuggingFace(settings: .init(
            apiKey: "key", baseURL: "https://proxy.example/v1/",
            headers: ["authorization": "Bearer custom-key", "X-Account": "account"], fetch: fetch
        ))("custom-model")
        let result = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "Policy", providerOptions: nil),
                .user(content: [
                    .text(.init(text: "Question")),
                    .file(.init(data: .base64("iVBORw0KGgo="), mediaType: "image")),
                    .file(.init(data: .url(URL(string: "https://media.example/image.png")!), mediaType: "image"))
                ], providerOptions: nil),
                .assistant(content: [
                    .reasoning(.init(text: "Thinking")), .text(.init(text: "Answer")),
                    .toolCall(.init(toolCallId: "call", toolName: "lookup", input: [:]))
                ], providerOptions: nil),
                .tool(content: [], providerOptions: nil)
            ],
            maxOutputTokens: 128, temperature: 0.4, stopSequences: ["stop"], topP: 0.8,
            topK: 5, presencePenalty: 0.1, frequencyPenalty: 0.2,
            responseFormat: .json(schema: schema, name: "answer", description: "A result"), seed: 7,
            tools: [
                .function(.init(name: "lookup", inputSchema: schema, description: "Lookup")),
                .provider(.init(id: "other.search", name: "search", args: [:]))
            ],
            toolChoice: .tool(toolName: "lookup"), headers: ["X-Request": "request"], reasoning: .high,
            providerOptions: ["huggingface": [
                "metadata": ["tenant": "one"], "instructions": "Be precise", "strictJsonSchema": true,
                "reasoningEffort": "custom-effort", "unknown": "ignored"
            ]]
        ))
        #expect(result.warnings == [
            .unsupported(feature: "topK", details: nil), .unsupported(feature: "seed", details: nil),
            .unsupported(feature: "presencePenalty", details: nil), .unsupported(feature: "frequencyPenalty", details: nil),
            .unsupported(feature: "stopSequences", details: nil), .unsupported(feature: "tool messages", details: nil),
            .unsupported(feature: "provider-defined tool other.search", details: nil)
        ])
    }

    @Test("inline bytes are base64 and wildcard media types are detected")
    func inlineBytes() async throws {
        let fetch: FetchFunction = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == ["model": "vision", "stream": false, "input": [
                ["role": "user", "content": [["type": "input_image", "image_url": "data:image/png;base64,iVBORw0KGgo="]]]
            ]])
            return try jsonResponse(request, responseValue())
        }
        _ = try await createHuggingFace(settings: .init(apiKey: "key", fetch: fetch))("vision").doGenerate(options: .init(
            prompt: [.user(content: [.file(.init(data: .data(Data([137, 80, 78, 71, 13, 10, 26, 10])), mediaType: "image/*"))], providerOptions: nil)]
        ))
    }

    @Test("unsupported V4 file representations fail before HTTP", arguments: [
        SharedV4FileData.reference(["huggingface": "file-id"]), .text("inline"), .base64("AQID")
    ])
    func unsupportedFiles(_ data: SharedV4FileData) async throws {
        let model = createHuggingFace(settings: .init(apiKey: "key"))("vision")
        let mediaType = data == .base64("AQID") ? "application/pdf" : "image/png"
        await #expect(throws: UnsupportedFunctionalityError.self) {
            try await model.doGenerate(options: .init(prompt: [.user(content: [.file(.init(data: data, mediaType: mediaType))], providerOptions: nil)]))
        }
    }

    @Test("generation preserves reasoning, sources, tool output strings and usage")
    func generationContract() async throws {
        let usage: JSONValue = [
            "input_tokens": 20, "input_tokens_details": ["cached_tokens": 5],
            "output_tokens": 12, "output_tokens_details": ["reasoning_tokens": 3], "total_tokens": 32
        ]
        let value = responseValue([
            "usage": usage, "incomplete_details": ["reason": "tool_calls"],
            "output": [
                ["type": "reasoning", "id": "r", "content": [["type": "reasoning_text", "text": "Thinking"]]],
                ["type": "message", "id": "m", "content": [["type": "output_text", "text": "Answer", "annotations": [["url": "https://example.com/source", "title": "Source"]]]]],
                ["type": "mcp_call", "id": "mc", "name": "search", "arguments": "{}", "output": "{\"found\":true}"],
                ["type": "function_call", "id": "fc", "call_id": "call", "name": "calculate", "arguments": "{}", "output": "42"],
                ["type": "mcp_list_tools", "id": "list-missing", "server_label": "server"],
                ["type": "mcp_list_tools", "id": "list-empty", "server_label": "server", "tools": []],
                ["type": "function_call", "id": "empty", "call_id": "empty-call", "name": "calculate", "arguments": "{}", "output": ""]
            ]
        ])
        let model = createHuggingFace(settings: .init(apiKey: "key", fetch: { try jsonResponse($0, value) }, generateId: { "source-id" }))("model")
        let result = try await model.doGenerate(options: .init(prompt: []))
        #expect(result.content == [
            .reasoning(.init(text: "Thinking", providerMetadata: ["huggingface": ["itemId": "r"]])),
            .text(.init(text: "Answer", providerMetadata: ["huggingface": ["itemId": "m"]])),
            .source(.url(id: "source-id", url: "https://example.com/source", title: "Source", providerMetadata: nil)),
            .toolCall(.init(toolCallId: "mc", toolName: "search", input: "{}", providerExecuted: true)),
            .toolResult(.init(toolCallId: "mc", toolName: "search", result: .string("{\"found\":true}"))),
            .toolCall(.init(toolCallId: "call", toolName: "calculate", input: "{}")),
            .toolResult(.init(toolCallId: "call", toolName: "calculate", result: .string("42"))),
            .toolCall(.init(toolCallId: "list-missing", toolName: "list_tools", input: "{\"server_label\":\"server\"}", providerExecuted: true)),
            .toolCall(.init(toolCallId: "list-empty", toolName: "list_tools", input: "{\"server_label\":\"server\"}", providerExecuted: true)),
            .toolResult(.init(toolCallId: "list-empty", toolName: "list_tools", result: ["tools": []])),
            .toolCall(.init(toolCallId: "empty-call", toolName: "calculate", input: "{}"))
        ])
        #expect(result.usage == .init(inputTokens: .init(total: 20, noCache: 15, cacheRead: 5), outputTokens: .init(total: 12, text: 9, reasoning: 3), raw: usage))
        #expect(result.finishReason == .init(unified: .toolCalls, raw: "tool_calls"))
        #expect(result.providerMetadata == ["huggingface": ["responseId": "response-id"]])
        #expect(result.response?.id == "response-id")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 123))
        #expect(result.response?.modelId == "returned-model")
    }

    @Test("unrepresentable usage remains raw without losing representable differences", arguments: [false, true])
    func numericUsage(huge: Bool) async throws {
        let usage: JSONValue = [
            "input_tokens": .number(huge ? 1e20 : Double(Int.min)), "input_tokens_details": ["cached_tokens": .number(huge ? 1e20 : 1)],
            "output_tokens": 2.5, "output_tokens_details": ["reasoning_tokens": 0.5], "total_tokens": 1e30
        ]
        let result = try await createHuggingFace(settings: .init(apiKey: "key", fetch: { try jsonResponse($0, responseValue(["usage": usage])) }))("model")
            .doGenerate(options: .init(prompt: []))
        #expect(result.usage == .init(
            inputTokens: .init(total: huge ? nil : Int.min, noCache: huge ? 0 : nil, cacheRead: huge ? nil : 1),
            outputTokens: .init(total: nil, text: 2, reasoning: nil), raw: usage
        ))
    }

    @Test("stream emits source event order and tolerates partial completed responses")
    func streamContract() async throws {
        let events = [
            #"{"type":"response.created","response":{"id":"response-id","object":"response","created_at":123,"status":"in_progress","model":"returned-model"}}"#,
            #"{"type":"response.output_item.added","item":{"type":"message","id":"user-message","role":"user"}}"#,
            #"{"type":"response.output_item.added","item":{"type":"reasoning","id":"r"}}"#,
            #"{"type":"response.reasoning_text.delta","item_id":"r","delta":"Thinking"}"#,
            #"{"type":"response.reasoning_text.done","item_id":"r","text":"Thinking"}"#,
            #"{"type":"response.output_item.done","item":{"type":"reasoning","id":"r"}}"#,
            #"{"type":"response.output_item.added","item":{"type":"message","id":"m","role":"assistant","content":[{"annotations":[{"url":"https://example.com"}]}]}}"#,
            #"{"type":"response.output_text.delta","item_id":"m","delta":"Answer"}"#,
            #"{"type":"response.output_item.done","item":{"type":"message","id":"m","role":"assistant"}}"#,
            #"{"type":"response.output_item.added","item":{"type":"function_call","call_id":"call","name":"calculate"}}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc","delta":"ignored"}"#,
            #"{"type":"response.output_item.done","item":{"type":"function_call","id":"fc","call_id":"call","name":"calculate","arguments":"{}","output":"42"}}"#,
            #"{"type":"response.output_item.added","item":{"type":"mcp_call","id":"mc","name":"search","arguments":"{}","output":"ignored"}}"#,
            #"{"type":"future.event","anything":true}"#,
            #"{"type":"response.completed","response":{"id":"response-id","usage":{"input_tokens":10,"output_tokens":8,"total_tokens":18}}}"#
        ]
        let fetch: FetchFunction = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Request") == "stream")
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == ["model": "model", "input": [], "stream": true])
            return eventResponse(request, events)
        }
        let result = try await createHuggingFace(settings: .init(apiKey: "key", fetch: fetch))("model").doStream(options: .init(
            prompt: [], includeRawChunks: true, headers: ["X-Request": "stream"]
        ))
        let parts = try await collect(result.stream)
        #expect(parts == [
            .streamStart(warnings: []),
            .responseMetadata(id: "response-id", modelId: "returned-model", timestamp: Date(timeIntervalSince1970: 123)),
            .reasoningStart(id: "r", providerMetadata: ["huggingface": ["itemId": "r"]]),
            .reasoningDelta(id: "r", delta: "Thinking", providerMetadata: nil), .reasoningEnd(id: "r", providerMetadata: nil),
            .textStart(id: "m", providerMetadata: ["huggingface": ["itemId": "m"]]),
            .textDelta(id: "m", delta: "Answer", providerMetadata: nil), .textEnd(id: "m", providerMetadata: nil),
            .toolInputStart(id: "call", toolName: "calculate", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputEnd(id: "call", providerMetadata: nil),
            .toolCall(.init(toolCallId: "call", toolName: "calculate", input: "{}")),
            .toolResult(.init(toolCallId: "call", toolName: "calculate", result: .string("42"))),
            .finish(finishReason: .init(unified: .stop, raw: nil), usage: .init(
                inputTokens: .init(total: 10, noCache: 10, cacheRead: 0), outputTokens: .init(total: 8, text: 8, reasoning: 0),
                raw: ["input_tokens": 10, "output_tokens": 8, "total_tokens": 18]
            ), providerMetadata: ["huggingface": ["responseId": "response-id"]])
        ])
    }

    @Test("provider stream errors preserve code, event type and raw payload", arguments: [
        #"{"type":"error","message":"Unavailable","code":503,"extra":true}"#,
        #"{"type":"error","message":"Unavailable","code":1e20,"extra":true}"#,
        #"{"type":"error","error":{"message":"Unavailable","code":"capacity"},"extra":true}"#,
        #"{"type":"response.failed","response":{"error":{"message":"Unavailable"}},"extra":true}"#
    ])
    func providerStreamErrors(_ event: String) async throws {
        let result = try await createHuggingFace(settings: .init(apiKey: "key", fetch: { eventResponse($0, [event]) }))("model").doStream(options: .init(prompt: []))
        let parts = try await collect(result.stream)
        let data = try JSONDecoder().decode(JSONValue.self, from: Data(event.utf8))
        guard case .error(.providerStreamError(let error)) = try #require(parts.dropFirst().first) else {
            Issue.record("Expected typed provider stream error"); return
        }
        #expect(error.message == "Unavailable")
        #expect(error.data == data)
        let isFailed = event.contains("response.failed")
        #expect(error.type == (isFailed ? "response.failed" : "error"))
        let numericCode: Double = event.contains("1e20") ? 1e20 : 503
        let numericRaw = event.contains("1e20") ? "100000000000000000000" : "503"
        #expect(error.code == (isFailed ? nil : event.contains("capacity") ? .string("capacity") : .number(numericCode)))
        #expect(parts.last == .finish(
            finishReason: .init(unified: .error, raw: isFailed ? "response.failed" : event.contains("capacity") ? "capacity" : numericRaw),
            usage: .init(), providerMetadata: ["huggingface": ["responseId": .null]]
        ))
    }

    @Test("invalid stream JSON is a typed parsing error followed by finish")
    func malformedStream() async throws {
        let result = try await createHuggingFace(settings: .init(apiKey: "key", fetch: { eventResponse($0, ["invalid json}"]) }))("model").doStream(options: .init(prompt: []))
        let parts = try await collect(result.stream)
        guard case .error(.error(let error)) = try #require(parts.dropFirst().first) else {
            Issue.record("Expected parser error"); return
        }
        #expect(error is JSONParseError)
        #expect(parts.last == .finish(finishReason: .init(unified: .error, raw: nil), usage: .init(), providerMetadata: ["huggingface": ["responseId": .null]]))
    }

    @Test("API failures retain HTTP diagnostics and in-band failures are nonretryable")
    func apiErrors() async throws {
        let fetch: FetchFunction = { request in
            try jsonResponse(request, ["error": ["message": "Capacity", "type": "overloaded", "code": "capacity"]], status: 429)
        }
        do {
            _ = try await createHuggingFace(settings: .init(apiKey: "key", fetch: fetch))("model").doGenerate(options: .init(prompt: []))
            Issue.record("Expected HTTP API failure")
        } catch let error as APICallError {
            #expect(error.message == "Capacity")
            #expect(error.statusCode == 429)
            #expect(error.isRetryable)
            #expect(error.responseHeaders?["x-request-id"] == "request-id")
            #expect(error.responseBody?.contains("capacity") == true)
        }
        let inBand: FetchFunction = { try jsonResponse($0, responseValue(["error": ["message": "Invalid model"]])) }
        do {
            _ = try await createHuggingFace(settings: .init(apiKey: "key", fetch: inBand))("model").doGenerate(options: .init(prompt: []))
            Issue.record("Expected in-band API failure")
        } catch let error as APICallError {
            #expect(error.message == "Invalid model")
            #expect(error.statusCode == 400)
            #expect(!error.isRetryable)
            let body = try #require(error.responseBody)
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)) == responseValue(["error": ["message": "Invalid model"]]))
        }
    }

    @Test("invalid provider options fail at the provider boundary")
    func invalidOptions() async throws {
        let model = createHuggingFace(settings: .init(apiKey: "key"))("model")
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(prompt: [], providerOptions: ["huggingface": ["reasoningEffort": .null]]))
        }
    }

    @Suite("lazy authentication", .serialized)
    struct Authentication {
        @Test("an existing model resolves the API key separately for each request")
        func perRequestKey() async throws {
            let original = getenv("HUGGINGFACE_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original { setenv("HUGGINGFACE_API_KEY", original, 1) }
                else { unsetenv("HUGGINGFACE_API_KEY") }
            }
            unsetenv("HUGGINGFACE_API_KEY")
            let model = createHuggingFace(settings: .init(fetch: { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer later-key")
                return try jsonResponse(request, responseValue())
            })).responses(.qwen314B)
            await #expect(throws: LoadAPIKeyError.self) {
                try await model.doGenerate(options: .init(prompt: []))
            }
            setenv("HUGGINGFACE_API_KEY", "later-key", 1)
            let result = try await model.doGenerate(options: .init(prompt: []))
            #expect(result.finishReason == .init(unified: .stop, raw: nil))
            #expect(result.usage == .init())
        }
    }
}

private func responseValue(_ overrides: [String: JSONValue] = [:]) -> JSONValue {
    .object([
        "id": "response-id", "model": "returned-model", "object": "response", "created_at": 123,
        "status": "completed", "error": .null, "instructions": .null, "max_output_tokens": .null,
        "metadata": .null, "tool_choice": "auto", "tools": [], "temperature": 1, "top_p": 1,
        "output": [], "usage": .null
    ].merging(overrides) { _, value in value })
}

private func jsonResponse(_ request: URLRequest, _ value: JSONValue, status: Int = 200) throws -> FetchResponse {
    FetchResponse(body: .data(try JSONEncoder().encode(value)), urlResponse: HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json", "X-Request-Id": "request-id"]
    )!)
}

private func eventResponse(_ request: URLRequest, _ events: [String]) -> FetchResponse {
    let text = events.map { "data:\($0)\n\n" }.joined()
    return FetchResponse(body: .data(Data(text.utf8)), urlResponse: HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]
    )!)
}

private func collect(_ stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>) async throws -> [LanguageModelV4StreamPart] {
    var parts: [LanguageModelV4StreamPart] = []
    for try await part in stream { parts.append(part) }
    return parts
}
