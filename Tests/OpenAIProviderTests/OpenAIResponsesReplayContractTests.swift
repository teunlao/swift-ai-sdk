import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses ordinary replay contracts")
struct OpenAIResponsesReplayContractTests {
    private actor Capture {
        var requests: [URLRequest] = []
        let reply: JSONValue
        init(_ reply: JSONValue = .object(["output": .array([])])) { self.reply = reply }
        func respond(_ request: URLRequest) throws -> FetchResponse {
            requests.append(request)
            return FetchResponse(body: .data(try JSONEncoder().encode(reply)), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!)
        }
        func input() throws -> [JSONValue] {
            let request = try #require(requests.last)
            let data = try #require(request.httpBody)
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            guard case .object(let body) = value, case .array(let input)? = body["input"] else {
                Issue.record("Missing Responses input"); return []
            }
            return input
        }
    }
    private func model(_ capture: Capture, id: String = "gpt-4.1") throws -> OpenAIResponsesLanguageModel {
        try createOpenAI(settings: .init(apiKey: "test", fetch: { try await capture.respond($0) })).responses(id)
    }
    private func function(_ name: String) -> LanguageModelV4Tool {
        .function(.init(name: name, inputSchema: .object(["type": .string("object")]), strict: false))
    }
    private let wrapper = #"{"tool_uses":[{"recipient_name":"functions.first","parameters":{"x":1}},{"recipient_name":"functions.second","parameters":{"x":2}}]}"#

    @Test("Provider option fallback distinguishes a missing namespace from an empty override", arguments: [false, true])
    func optionNamespaces(emptyOverride: Bool) async throws {
        let capture = Capture()
        let model = OpenAIResponsesLanguageModel(modelId: "gpt-4.1", config: .init(
            provider: "proxy-azure\u{0301}.responses", url: { _ in "https://api.openai.test/responses" }, headers: { [:] },
            fetch: { try await capture.respond($0) }
        ))
        var options: SharedV4ProviderOptions = ["openai": ["store": .bool(false)]]
        if emptyOverride { options["azure"] = [:] }
        _ = try await model.doGenerate(options: .init(prompt: [
            .assistant(content: [.text(.init(text: "text", providerOptions: ["azure": ["itemId": .string("azure_msg")], "openai": ["itemId": .string("other_msg")]]))], providerOptions: nil)
        ], providerOptions: options))
        #expect(try await capture.input() == [emptyOverride
            ? .object(["type": .string("item_reference"), "id": .string("azure_msg")])
            : .object(["role": .string("assistant"), "content": .string("text")])])
    }

    @Test("Client calls reconstruct identity and JSON values across stored chains", arguments: [false, true])
    func clientCalls(previous: Bool) async throws {
        let capture = Capture()
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [
                .toolCall(.init(toolCallId: "call_one", toolName: "lookup", input: .object(["n": .number(1e20)]), providerOptions: ["openai": ["itemId": .string("fc_one"), "async": .bool(false), "namespace": .string("")]])),
                .toolCall(.init(toolCallId: "call_two", toolName: "tool_search", input: .string(""), providerOptions: ["openai": ["itemId": .string("fc_two")]]))
            ], providerOptions: nil),
            .tool(content: [
                .toolResult(.init(toolCallId: "call_one", toolName: "lookup", output: .errorText(value: "bad"))),
                .toolResult(.init(toolCallId: "call_two", toolName: "tool_search", output: .json(value: .string(""))))
            ], providerOptions: nil)
        ]
        _ = try await model(capture).doGenerate(options: .init(
            prompt: prompt, tools: [function("lookup"), function("tool_search")],
            providerOptions: previous ? ["openai": ["previousResponseId": .string("previous")]] : nil
        ))
        let input = try await capture.input()
        #expect(input == [
            .object(["type": .string("function_call"), "call_id": .string("call_one"), "name": .string("lookup"), "arguments": .string("{\"n\":100000000000000000000}"), "async": .bool(false), "namespace": .string("")]),
            .object(["type": .string("function_call"), "call_id": .string("call_two"), "name": .string("tool_search"), "arguments": .string("\"\"")]),
            .object(["type": .string("function_call_output"), "call_id": .string("call_one"), "output": .string("{\"error\":\"bad\"}")]),
            .object(["type": .string("function_call_output"), "call_id": .string("call_two"), "output": .string("\"\"")])
        ])
    }

    @Test("Stored assistant text references require preceding reasoning and are deduplicated")
    func reasoningBoundText() async throws {
        let capture = Capture()
        _ = try await model(capture, id: "gpt-5").doGenerate(options: .init(prompt: [
            .assistant(content: [
                .text(.init(text: "before", providerOptions: ["openai": ["itemId": .string("msg")]])),
                .reasoning(.init(text: "thought", providerOptions: ["openai": ["itemId": .string("rs")]])),
                .text(.init(text: "after", providerOptions: ["openai": ["itemId": .string("msg")]])),
                .text(.init(text: "again", providerOptions: ["openai": ["itemId": .string("msg")]]))
            ], providerOptions: nil)
        ]))
        #expect(try await capture.input() == [
            .object(["role": .string("assistant"), "content": .string("before")]),
            .object(["type": .string("item_reference"), "id": .string("rs")]),
            .object(["type": .string("item_reference"), "id": .string("msg")])
        ])
    }

    @Test("Store-false history sends only replayable encrypted reasoning")
    func encryptedReasoning() async throws {
        let capture = Capture()
        let result = try await model(capture, id: "gpt-5").doGenerate(options: .init(prompt: [
            .assistant(content: [
                .reasoning(.init(text: "kept", providerOptions: ["openai": ["itemId": .string("keep"), "reasoningEncryptedContent": .string("encrypted")]])),
                .reasoning(.init(text: "dropped", providerOptions: ["openai": ["itemId": .string("drop")]]))
            ], providerOptions: nil)
        ], providerOptions: ["openai": ["store": .bool(false)]]))
        #expect(try await capture.input() == [.object([
            "type": .string("reasoning"), "id": .string("keep"), "encrypted_content": .string("encrypted"),
            "summary": .array([.object(["type": .string("summary_text"), "text": .string("kept")])])
        ])])
        #expect(result.warnings.contains { if case .other = $0 { return true }; return false })
    }

    @Test("User media resolves wildcard types and provider references without losing null detail")
    func userFiles() async throws {
        let capture = Capture()
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0])
        _ = try await model(capture).doGenerate(options: .init(prompt: [
            .user(content: [
                .text(.init(text: "")),
                .file(.init(data: .data(png), mediaType: "image", providerOptions: ["openai": ["imageDetail": .null]])),
                .file(.init(data: .reference(["openai": "file_generic"]), mediaType: "application/octet-stream")),
                .file(.init(data: .base64("file-\u{0301}id"), mediaType: "image/jpeg"))
            ], providerOptions: nil)
        ]))
        #expect(try await capture.input() == [.object(["role": .string("user"), "content": .array([
            .object(["type": .string("input_text"), "text": .string("")]),
            .object(["type": .string("input_image"), "image_url": .string("data:image/png;base64,\(png.base64EncodedString())"), "detail": .null]),
            .object(["type": .string("input_file"), "file_id": .string("file_generic")]),
            .object(["type": .string("input_image"), "file_id": .string("file-\u{0301}id")])
        ])])])
    }

    @Test("Provider web-search results reconstruct ordinary store-false history")
    func webSearchReplay() async throws {
        let first = Capture(.object(["output": .array([.object([
            "type": .string("web_search_call"), "id": .string("ws"), "status": .string("completed"),
            "action": .object(["type": .string("search"), "queries": .array([.string("query")])])
        ])])]))
        let tools: [LanguageModelV4Tool] = [.provider(.init(id: "openai.web_search", name: "search", args: [:]))]
        let generated = try await model(first).doGenerate(options: .init(prompt: [], tools: tools))
        let result = try #require(generated.content.compactMap { part -> LanguageModelV4ToolResult? in if case .toolResult(let result) = part { return result }; return nil }.first)
        let next = Capture()
        _ = try await model(next).doGenerate(options: .init(prompt: [
            .assistant(content: [.toolResult(.init(toolCallId: result.toolCallId, toolName: result.toolName, output: .json(value: result.result)))], providerOptions: nil)
        ], tools: tools, providerOptions: ["openai": ["store": .bool(false)]]))
        #expect(try await next.input() == [.object([
            "type": .string("web_search_call"), "id": .string("ws"), "status": .string("completed"),
            "action": .object(["type": .string("search"), "queries": .array([.string("query")])])
        ])])
    }

    @Test("Parallel wrappers expand only undeclared wrappers with fully declared recipients", arguments: ["valid", "declared", "invalid"])
    func parallelGenerate(kind: String) async throws {
        let input = kind == "invalid" ? #"{"tool_uses":[{"recipient_name":"functions.first","parameters":{}},{"recipient_name":"functions.unknown","parameters":{}}]}"# : wrapper
        let capture = Capture(.object(["output": .array([.object([
            "type": .string("function_call"), "id": .string("fc_wrapper"), "call_id": .string("call_wrapper"), "name": .string("parallel"), "arguments": .string(input)
        ])])]))
        var tools = [function("first"), function("second")]
        if kind == "declared" { tools.append(function("parallel")) }
        let result = try await model(capture).doGenerate(options: .init(prompt: [], tools: tools))
        let calls = result.content.compactMap { part -> LanguageModelV4ToolCall? in if case .toolCall(let call) = part { return call }; return nil }
        if kind == "valid" {
            #expect(calls.map(\.toolName) == ["first", "second"])
            #expect(calls.map(\.toolCallId) == ["call_wrapper_0", "call_wrapper_1"])
            for (index, call) in calls.enumerated() {
                let metadata = try #require(call.providerMetadata?["openai"]?["parallelToolCall"])
                #expect(metadata == parallelMetadata(index: Double(index), count: 2)["openai"]?["parallelToolCall"])
                #expect(try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8)) == .object(["x": .number(Double(index + 1))]))
            }
        } else {
            #expect(calls.map(\.toolName) == ["parallel"])
            #expect(calls.first?.input == input)
        }
    }

    @Test("Parallel streaming expands valid wrappers and replays invalid or unfinished inputs once", arguments: ["valid", "invalid", "invalid_without_deltas", "incomplete"])
    func parallelStream(kind: String) async throws {
        let invalid = kind == "invalid" || kind == "invalid_without_deltas"
        let input = invalid ? #"{"tool_uses":[{"recipient_name":"functions.unknown","parameters":{}}]}"# : wrapper
        let split = input.index(input.startIndex, offsetBy: input.count / 2)
        let deltas = kind == "invalid_without_deltas" ? [] : [String(input[..<split]), String(input[split...])]
        var frames: [JSONValue] = [.object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": .object([
            "type": .string("function_call"), "id": .string("fc_wrapper"), "call_id": .string("call_wrapper"), "name": .string("parallel"), "arguments": .string("")
        ])])]
        for delta in deltas { frames.append(.object(["type": .string("response.function_call_arguments.delta"), "item_id": .string("fc_wrapper"), "output_index": .number(0), "delta": .string(delta)])) }
        if kind != "incomplete" {
            frames.append(.object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object([
                "type": .string("function_call"), "id": .string("fc_wrapper"), "call_id": .string("call_wrapper"), "name": .string("parallel"), "arguments": .string(input), "status": .string("completed")
            ])]))
        }
        frames.append(.object(["type": .string("response.completed"), "response": .object([:])]))
        var data = Data()
        for frame in frames { data.append(Data("data: ".utf8)); data.append(try JSONEncoder().encode(frame)); data.append(Data("\n\n".utf8)) }
        data.append(Data("data: [DONE]\n\n".utf8))
        let body = data
        let provider = try createOpenAI(settings: .init(apiKey: "test", fetch: { request in
            FetchResponse(body: .data(body), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        let result = try await provider.responses("gpt-4.1").doStream(options: .init(prompt: [], tools: [function("first"), function("second")]))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        let calls = parts.compactMap { part -> LanguageModelV4ToolCall? in if case .toolCall(let call) = part { return call }; return nil }
        if kind == "valid" {
            #expect(calls.map(\.toolCallId) == ["call_wrapper_0", "call_wrapper_1"])
            #expect(calls.map(\.toolName) == ["first", "second"])
            let starts = parts.compactMap { part -> String? in if case .toolInputStart(let id, _, _, _, _, _, _) = part { return id }; return nil }
            #expect(starts == ["call_wrapper_0", "call_wrapper_1"])
        } else {
            let events = parts.compactMap { part -> String? in
                switch part {
                case .toolInputStart(let id, _, _, _, _, _, _): return "start:\(id)"
                case .toolInputDelta(let id, let delta, _): return "delta:\(id):\(delta)"
                case .toolInputEnd(let id, _): return "end:\(id)"
                case .toolCall(let call): return "call:\(call.toolCallId)"
                default: return nil
                }
            }
            let replayed = deltas.isEmpty ? [input] : deltas
            var expected = ["start:call_wrapper"] + replayed.map { "delta:call_wrapper:\($0)" }
            if invalid { expected += ["end:call_wrapper", "call:call_wrapper"] }
            #expect(events == expected)
            #expect(calls.first?.input == (invalid ? input : nil))
        }
    }

    private func parallelMetadata(index: Double, count: Double) -> SharedV4ProviderOptions {
        ["openai": ["parallelToolCall": .object([
            "itemId": .string("fc_wrapper"), "toolCallId": .string("call_wrapper"), "toolName": .string("parallel"),
            "input": .string(wrapper), "index": .number(index), "count": .number(count)
        ])]]
    }

    @Test("Parallel wrapper identities use literal strings rather than Unicode normalization")
    func literalWrapperIdentity() async throws {
        let capture = Capture()
        let input = #"{"tool_uses":[{"recipient_name":"functions.first","parameters":{"n":1}}]}"#
        let ids = ["K", "\u{212A}"]
        var calls: [LanguageModelV4MessagePart] = []
        var outputs: [LanguageModelV4ToolMessagePart] = []
        for id in ids {
            let metadata: SharedV4ProviderOptions = ["openai": ["parallelToolCall": .object([
                "itemId": .string("fc_\(id)"), "toolCallId": .string(id), "toolName": .string("parallel"),
                "input": .string(input), "index": .number(0), "count": .number(1)
            ])]]
            calls.append(.toolCall(.init(toolCallId: "\(id)_0", toolName: "first", input: .object(["n": .number(1)]), providerOptions: metadata)))
            outputs.append(.toolResult(.init(toolCallId: "\(id)_0", toolName: "first", output: .text(value: id), providerOptions: metadata)))
        }
        _ = try await model(capture).doGenerate(options: .init(prompt: [
            .assistant(content: calls, providerOptions: nil), .tool(content: outputs, providerOptions: nil)
        ], tools: [function("first")], providerOptions: ["openai": ["previousResponseId": .string("previous")]]))
        let encoded = try await capture.input()
        let callIds = encoded.compactMap { value -> [UInt8]? in
            guard case .object(let object) = value, case .string(let id)? = object["call_id"] else { return nil }
            return Array(id.utf8)
        }
        #expect(callIds == (ids + ids).map { Array($0.utf8) })
    }

    @Test("Server-state replay reunites only complete parallel groups in original order", arguments: ["previous", "conversation", "incomplete"])
    func parallelReplay(context: String) async throws {
        let capture = Capture()
        let count = context == "incomplete" ? 1e20 : 2.0
        let first = parallelMetadata(index: 0, count: count)
        let second = parallelMetadata(index: 1, count: count)
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [
                .toolCall(.init(toolCallId: "call_wrapper_0", toolName: "first", input: .object(["x": .number(1)]), providerOptions: first)),
                .toolCall(.init(toolCallId: "call_wrapper_1", toolName: "second", input: .object(["x": .number(2)]), providerOptions: second))
            ], providerOptions: nil),
            .tool(content: [
                .toolResult(.init(toolCallId: "call_wrapper_1", toolName: "second", output: .errorJson(value: .object(["code": .number(7)])), providerOptions: second)),
                .toolResult(.init(toolCallId: "call_wrapper_0", toolName: "first", output: .text(value: "first-result"), providerOptions: first))
            ], providerOptions: nil)
        ]
        _ = try await model(capture).doGenerate(options: .init(
            prompt: prompt, tools: [function("first"), function("second")],
            providerOptions: ["openai": [context == "conversation" ? "conversation" : "previousResponseId": .string("context")]]
        ))
        let input = try await capture.input()
        if context == "incomplete" {
            #expect(input.count == 4)
            #expect(input.contains(.object(["type": .string("function_call_output"), "call_id": .string("call_wrapper_0"), "output": .string("first-result")])))
            #expect(input.contains(.object(["type": .string("function_call_output"), "call_id": .string("call_wrapper_1"), "output": .string("{\"error\":{\"code\":7}}")])) )
        } else {
            var expected: [JSONValue] = []
            if context == "previous" {
                expected.append(.object(["type": .string("function_call"), "call_id": .string("call_wrapper"), "name": .string("parallel"), "arguments": .string(wrapper)]))
            }
            expected.append(.object(["type": .string("function_call_output"), "call_id": .string("call_wrapper"), "output": .string("first-result\n{\"error\":{\"code\":7}}")]))
            #expect(input == expected)
        }
    }
}
