import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let advancedTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func makeAdvancedConfig(
    fetch: @escaping FetchFunction,
    headers: @escaping @Sendable () -> [String: String?] = {
        [
            "x-api-key": "test-key",
            "anthropic-version": "2023-06-01"
        ]
    }
) -> AnthropicMessagesConfig {
    AnthropicMessagesConfig(
        provider: "anthropic.messages",
        baseURL: "https://api.anthropic.com/v1",
        headers: headers,
        fetch: fetch,
        supportedUrls: { [:] },
        generateId: { "generated-id" }
    )
}

private func makeStream(from events: [String]) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(Data(event.utf8))
        }
        continuation.finish()
    }
}

private func collectParts(from stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
    var parts: [LanguageModelV3StreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

private func events(from payloads: [String], appendDone: Bool = false) -> [String] {
    var items = payloads.map { "data: \($0)\n\n" }
    if appendDone {
        items.append("data: [DONE]\n\n")
    }
    return items
}

private func loadFixtureEvents(_ name: String) throws -> [String] {
    let path = "external/vercel-ai-sdk/packages/anthropic/src/__fixtures__/\(name).chunks.txt"
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    let payloads = contents.split(separator: "\n").map(String.init)
    return events(from: payloads, appendDone: true)
}

private func makeHTTPResponse(headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: headers
    )!
}

private actor RequestCapture {
    private var currentRequest: URLRequest?

    func store(_ request: URLRequest) {
        currentRequest = request
    }

    func value() -> URLRequest? {
        currentRequest
    }
}

@Suite("AnthropicMessagesLanguageModel stream advanced")
struct AnthropicMessagesLanguageModelStreamAdvancedTests {
    @Test("streams json response format as text deltas")
    func streamJsonResponseFormat() async throws {
        let capture = RequestCapture()
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01GouTqNCGXzrj5LQ5jEkw67","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":441,"output_tokens":2},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"ping"}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Okay"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01DBsB4vvYLnBDzZ5rBSxSLs","name":"json","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"value"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\":"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Spark"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"le"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" Day\"}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":441,"output_tokens":65}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
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

        let result = try await model.doStream(options: .init(
            prompt: advancedTestPrompt,
            responseFormat: .json(schema: schema, name: nil, description: nil)
        ))

        let parts = try await collectParts(from: result.stream)
        guard case .streamStart(let warnings) = parts.first else {
            Issue.record("Missing stream start")
            return
        }
        #expect(warnings.isEmpty)

        let jsonText = parts.compactMap { part -> String? in
            if case .textDelta(let id, let delta, _) = part, id == "1" { return delta }
            return nil
        }.joined()
        #expect(jsonText == "{\"value\":\"Sparkle Day\"}")

        #expect(parts.contains { if case .toolCall = $0 { return true } else { return false } } == false)

        if let finishPart = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
           case .finish(let finishReason, let usage, let metadata) = finishPart {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 441)
            #expect(usage.outputTokens == 65)
            let anthropicUsage = metadata?["anthropic"]?["usage"]
            #expect(anthropicUsage == .object([
                "input_tokens": .number(441),
                "output_tokens": .number(65)
            ]))
        } else {
            Issue.record("Missing finish part")
        }

        if let request = await capture.value(),
           let body = request.httpBody,
           let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
           let toolChoice = json["tool_choice"] as? [String: Any],
           let tools = json["tools"] as? [[String: Any]] {
            #expect(json["stream"] as? Bool == true)
            #expect(toolChoice["name"] as? String == "json")
            #expect(toolChoice["type"] as? String == "tool")
            #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)
            #expect(tools.count == 1)
            #expect(tools.first?["name"] as? String == "json")
        } else {
            Issue.record("Missing request body payload")
        }
    }

    @Test("streams function tool input and emits tool call")
    func streamFunctionTool() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01GouTqNCGXzrj5LQ5jEkw67","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":441,"output_tokens":2},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"ping"}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Okay"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01DBsB4vvYLnBDzZ5rBSxSLs","name":"test-tool","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"value"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\":"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Spark"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"le"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" Day\"}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":441,"output_tokens":65}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let toolSchema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": .string("string")])
            ]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        let result = try await model.doStream(options: .init(
            prompt: advancedTestPrompt,
            tools: [
                .function(LanguageModelV3FunctionTool(name: "test-tool", inputSchema: toolSchema))
            ]
        ))

        let parts = try await collectParts(from: result.stream)
        let toolInputStart = parts.first { part in
            if case .toolInputStart(let id, let toolName, _, let providerExecuted) = part {
                return id == "toolu_01DBsB4vvYLnBDzZ5rBSxSLs" && toolName == "test-tool" && providerExecuted == false
            }
            return false
        }
        #expect(toolInputStart != nil)

        let toolInput = parts.compactMap { part -> String? in
            if case .toolInputDelta(let id, let delta, _) = part, id == "toolu_01DBsB4vvYLnBDzZ5rBSxSLs" { return delta }
            return nil
        }.joined()
        #expect(toolInput == "{\"value\":\"Sparkle Day\"}")

        let toolCall = parts.first { part in
            if case .toolCall(let call) = part {
                return call.toolCallId == "toolu_01DBsB4vvYLnBDzZ5rBSxSLs" && call.toolName == "test-tool" && call.input == "{\"value\":\"Sparkle Day\"}" && call.providerExecuted == false
            }
            return false
        }
        #expect(toolCall != nil)

        if let finishPart = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
           case .finish(let finishReason, _, _) = finishPart {
            #expect(finishReason == .toolCalls)
        } else {
            Issue.record("Missing finish part")
        }
    }

    @Test("streams reasoning blocks with signature metadata")
    func streamReasoningWithSignature() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"I am"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"thinking..."}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"1234567890"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":17,"output_tokens":227}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(prompt: advancedTestPrompt))
        let parts = try await collectParts(from: result.stream)

        let reasoningDeltas = parts.compactMap { part -> (String, String)? in
            if case .reasoningDelta(let id, let delta, _) = part {
                return (id, delta)
            }
            return nil
        }
        #expect(reasoningDeltas.contains(where: { $0.0 == "0" && $0.1 == "I am" }))
        #expect(reasoningDeltas.contains(where: { $0.0 == "0" && $0.1 == "thinking..." }))
        #expect(reasoningDeltas.count >= 2)
    }

    @Test("streams redacted reasoning metadata")
    func streamRedactedReasoning() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"redacted_thinking","data":"redacted-thinking-data"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello, World!"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":17,"output_tokens":227}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(prompt: advancedTestPrompt))
        let parts = try await collectParts(from: result.stream)

        guard let startPart = parts.first(where: { if case .reasoningStart = $0 { return true } else { return false } }),
              case .reasoningStart(let id, let metadata) = startPart else {
            Issue.record("Missing reasoning start")
            return
        }

        #expect(id == "0")
        #expect(metadata?["anthropic"]?["redactedData"] == .string("redacted-thinking-data"))
    }

    @Test("forwards error chunks during streaming")
    func streamErrorChunk() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01KfpJoAEabmH2iHRRFjQMAG","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"ping"}"#,
            #"{"type":"error","error":{"type":"error","message":"test error"}}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(prompt: advancedTestPrompt))
        let parts = try await collectParts(from: result.stream)

        let errorPart = parts.first { if case .error = $0 { return true } else { return false } }
        #expect(errorPart != nil)
        if case .error(let error) = errorPart,
           case .object(let outer) = error,
           case .object(let payload)? = outer["error"] {
            #expect(payload["message"] == .string("test error"))
            #expect(payload["type"] == .string("error"))
        } else {
            Issue.record("Unexpected error payload")
        }
    }

    @Test("includes raw chunks when requested")
    func includeRawChunks() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":17,"output_tokens":227}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: advancedTestPrompt,
            includeRawChunks: true
        ))

        let parts = try await collectParts(from: result.stream)
        let rawCount = parts.filter { if case .raw = $0 { return true } else { return false } }.count
        #expect(rawCount == payloads.count)
    }

    @Test("omits raw chunks when not requested")
    func omitRawChunks() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":17,"output_tokens":227}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(prompt: advancedTestPrompt))
        let parts = try await collectParts(from: result.stream)
        let rawCount = parts.filter { if case .raw = $0 { return true } else { return false } }.count
        #expect(rawCount == 0)
    }

    @Test("propagates stop sequence metadata")
    func stopSequenceMetadata() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"stop_sequence","stop_sequence":"STOP"},"usage":{"input_tokens":17,"output_tokens":227}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: advancedTestPrompt,
            stopSequences: ["STOP"]
        ))

        let parts = try await collectParts(from: result.stream)
        guard let finishPart = parts.first(where: { if case .finish = $0 { return true } else { return false } }),
              case .finish(_, _, let metadata) = finishPart else {
            Issue.record("Missing finish part")
            return
        }

        #expect(metadata?["anthropic"]?["stopSequence"] == .string("STOP"))
    }

    @Test("propagates cache control metadata")
    func cacheControlMetadata() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1,"cache_creation_input_tokens":10,"cache_read_input_tokens":5},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"ping"}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":17,"output_tokens":227}}"#,
            #"{"type":"message_stop"}"#
        ]
        let events = events(from: payloads)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(prompt: advancedTestPrompt))
        let parts = try await collectParts(from: result.stream)
        guard let finishPart = parts.first(where: { if case .finish = $0 { return true } else { return false } }),
              case .finish(_, let usage, let metadata) = finishPart else {
            Issue.record("Missing finish part")
            return
        }

        #expect(usage.cachedInputTokens == 5)
        #expect(metadata?["anthropic"]?["cacheCreationInputTokens"] == .number(10))
        if case .object(let usageMetadata) = metadata?["anthropic"]?["usage"] {
            #expect(usageMetadata["cache_creation_input_tokens"] == .number(10))
            #expect(usageMetadata["cache_read_input_tokens"] == .number(5))
        } else {
            Issue.record("Missing usage metadata")
        }
    }

    @Test("streams provider executed web fetch tool results")
    func providerExecutedWebFetch() async throws {
        let events = try loadFixtureEvents("anthropic-web-fetch-tool.1")
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-20250514"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: advancedTestPrompt,
            tools: [
                .providerDefined(
                    LanguageModelV3ProviderDefinedTool(
                        id: "anthropic.web_fetch_20250910",
                        name: "web_fetch",
                        args: ["maxUses": .number(1)]
                    )
                )
            ]
        ))

        let parts = try await collectParts(from: result.stream)
        let toolInputStart = parts.first { part in
            if case .toolInputStart(_, let toolName, _, let providerExecuted) = part {
                return toolName == "web_fetch" && providerExecuted == true
            }
            return false
        }
        #expect(toolInputStart != nil)

        let toolResult = parts.first { part in
            if case .toolResult(let result) = part {
                return result.toolName == "web_fetch" && result.providerExecuted == true
            }
            return false
        }
        #expect(toolResult != nil)
        if case .toolResult(let result) = toolResult,
           case .object(let payload) = result.result {
            #expect(payload["type"] == .string("web_fetch_result"))
        } else {
            Issue.record("Unexpected web fetch payload")
        }
    }

    @Test("streams provider executed web search tool results")
    func providerExecutedWebSearch() async throws {
        let events = try loadFixtureEvents("anthropic-web-search-tool.1")
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: events)), urlResponse: makeHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeAdvancedConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: advancedTestPrompt,
            tools: [
                .providerDefined(
                    LanguageModelV3ProviderDefinedTool(
                        id: "anthropic.web_search_20250305",
                        name: "web_search",
                        args: [
                            "maxUses": .number(1),
                            "userLocation": .object([
                                "type": .string("approximate"),
                                "country": .string("US")
                            ])
                        ]
                    )
                )
            ]
        ))

        let parts = try await collectParts(from: result.stream)
        let toolResult = parts.first { part in
            if case .toolResult(let result) = part {
                return result.toolName == "web_search" && result.providerExecuted == true
            }
            return false
        }
        #expect(toolResult != nil)
        if case .toolResult(let result) = toolResult {
            switch result.result {
            case .array(let array):
                #expect(!array.isEmpty)
            case .object(let object):
                #expect(object["type"] == .string("web_search_tool_result_error"))
            default:
                Issue.record("Unexpected web search payload")
            }
        }

        let sourcesCount = parts.reduce(0) { count, part in
            if case .source = part { return count + 1 } else { return count }
        }
        #expect(sourcesCount > 0)
    }
}
