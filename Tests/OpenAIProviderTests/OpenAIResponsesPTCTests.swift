import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses hosted PTC wire contracts")
struct OpenAIResponsesPTCTests {
    private actor Endpoint {
        let data: Data
        let streaming: Bool
        var body: JSONValue?
        init(output: [JSONValue] = []) throws { data = try JSONEncoder().encode(JSONValue.object(["output": .array(output)])); streaming = false }
        init(frames: [JSONValue]) throws {
            data = Data(try frames.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
            streaming = true
        }
        func fetch(_ request: URLRequest) throws -> FetchResponse {
            body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!)
        }
        func value() -> JSONValue? { body }
    }
    private let code = "throw new Error('hosted data only');\ntext('e\u{0301}');"
    private let fingerprint = "opaque:e\u{0301}/fingerprint"
    private var program: JSONValue { .object([
        "type": .string("program"), "id": .string("program_item"), "call_id": .string("parent"), "code": .string(code), "fingerprint": .string(fingerprint)
    ]) }
    private let child: JSONValue = .object([
        "type": .string("function_call"), "id": .string("child_item"), "call_id": .string("child"), "name": .string("lookup"), "arguments": .string("{}"),
        "status": .string("completed"), "caller": .object(["type": .string("program"), "caller_id": .string("parent")])
    ])
    private let programOutput: JSONValue = .object([
        "type": .string("program_output"), "id": .string("output_item"), "call_id": .string("parent"), "result": .string("result\n"), "status": .string("incomplete")
    ])
    private var tools: [LanguageModelV4Tool] {
        let tool = openaiTools.programmaticToolCalling()
        return [
            .provider(.init(id: tool.id!, name: "orchestrate", args: tool.args ?? [:])),
            .function(.init(name: "lookup", inputSchema: .object(["type": .string("object")]), providerOptions: ["openai": ["allowedCallers": .array([.string("direct")])]]))
        ]
    }
    private func model(_ endpoint: Endpoint) throws -> OpenAIResponsesLanguageModel {
        try createOpenAI(settings: .init(apiKey: "test", fetch: { try await endpoint.fetch($0) })).responses("gpt-6")
    }
    private let caller: JSONValue = .object(["type": .string("program"), "callerId": .string("parent")])

    @Test("Hosted programs and child caller metadata round-trip through store-false history")
    func generateReplay() async throws {
        let endpoint = try Endpoint(output: [program, child, programOutput])
        let generated = try await model(endpoint).doGenerate(options: .init(prompt: [], tools: tools, toolChoice: .tool(toolName: "orchestrate")))
        guard case .object(let body)? = await endpoint.value(), case .array(let wireTools)? = body["tools"] else { Issue.record("Missing tools"); return }
        let function = try #require(wireTools.compactMap { value -> [String: JSONValue]? in
            if case .object(let value) = value, value["type"] == .string("function") { return value }; return nil
        }.first)
        #expect(wireTools.first == .object(["type": .string("programmatic_tool_calling")]))
        #expect(body["tool_choice"] == .object(["type": .string("programmatic_tool_calling")]))
        #expect(function["allowed_callers"] == .array([.string("direct")]))
        #expect(generated.finishReason.unified == .toolCalls)
        let calls = generated.content.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }
        let result = try #require(generated.content.compactMap { if case .toolResult(let result) = $0 { return result }; return nil }.first)
        #expect(calls.count == 2)
        let hosted = try #require(calls.first)
        #expect(hosted.toolCallId == "parent" && hosted.toolName == "orchestrate" && hosted.providerExecuted == true)
        #expect(hosted.providerMetadata?["openai"]?["itemId"] == .string("program_item"))
        #expect(calls.last?.providerMetadata?["openai"]?["caller"] == caller)
        #expect(result.toolCallId == "parent" && result.toolName == "orchestrate")
        #expect(result.providerMetadata?["openai"]?["itemId"] == .string("output_item"))
        #expect(result.result == .object(["result": .string("result\n"), "status": .string("incomplete")]))
        let next = try Endpoint()
        let content: [LanguageModelV4MessagePart] = try calls.map { call in
            .toolCall(.init(toolCallId: call.toolCallId, toolName: call.toolName, input: try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8)), providerExecuted: call.providerExecuted, providerOptions: call.providerMetadata))
        } + [.toolResult(.init(toolCallId: result.toolCallId, toolName: result.toolName, output: .json(value: result.result), providerOptions: result.providerMetadata))]
        _ = try await model(next).doGenerate(options: .init(prompt: [
            .assistant(content: content, providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "child", toolName: "lookup", output: .text(value: "child result"), providerOptions: ["openai": ["caller": caller]]))], providerOptions: nil)
        ], tools: tools, providerOptions: ["openai": ["store": .bool(false)]]))
        guard case .object(let replay)? = await next.value(), case .array(let items)? = replay["input"], items.count == 4,
              case .object(let replayProgram) = items[0], case .string(let replayCode)? = replayProgram["code"], case .string(let replayFingerprint)? = replayProgram["fingerprint"] else {
            Issue.record("Missing PTC replay"); return
        }
        #expect(Data(replayCode.utf8) == Data(code.utf8))
        #expect(Data(replayFingerprint.utf8) == Data(fingerprint.utf8))
        #expect(items[0] == program)
        #expect(items[1] == .object(["type": .string("function_call"), "call_id": .string("child"), "name": .string("lookup"), "arguments": .string("{}"), "caller": .object(["type": .string("program"), "caller_id": .string("parent")])]))
        #expect(items[2] == programOutput)
        #expect(items[3] == .object(["type": .string("function_call_output"), "call_id": .string("child"), "output": .string("child result"), "caller": .object(["type": .string("program"), "caller_id": .string("parent")])]))
    }

    @Test("Program stream emits deferred hosted call and result only on done, with child caller metadata")
    func streamOrdering() async throws {
        let endpoint = try Endpoint(frames: [
            .object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": program]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": program]),
            .object(["type": .string("response.output_item.added"), "output_index": .number(0.5), "item": child]),
            .object(["type": .string("response.function_call_arguments.delta"), "item_id": .string("child_item"), "output_index": .number(0.5), "delta": .string("{}")]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(0.5), "item": child]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(1e20), "item": programOutput]),
            .object(["type": .string("response.completed"), "response": .object([:])])
        ])
        let response = try await model(endpoint).doStream(options: .init(prompt: [], tools: tools))
        var sequence: [String] = []
        for try await part in response.stream {
            switch part {
            case .toolInputStart(let id, _, _, _, _, _, _): #expect(id == "child"); sequence.append("child-start")
            case .toolInputDelta(let id, _, _): #expect(id == "child"); sequence.append("child-delta")
            case .toolInputEnd(let id, _): #expect(id == "child"); sequence.append("child-end")
            case .toolCall(let call):
                if call.toolCallId == "parent" {
                    #expect(call.providerExecuted == true && call.toolName == "orchestrate")
                    #expect(try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8)) == .object(["code": .string(code), "fingerprint": .string(fingerprint)]))
                    #expect(call.providerMetadata?["openai"]?["itemId"] == .string("program_item")); sequence.append("program")
                } else { #expect(call.providerMetadata?["openai"]?["caller"] == caller); sequence.append("child") }
            case .toolResult(let result):
                #expect(result.toolName == "orchestrate" && result.toolCallId == "parent")
                #expect(result.providerMetadata?["openai"]?["itemId"] == .string("output_item"))
                #expect(result.result == .object(["result": .string("result\n"), "status": .string("incomplete")])); sequence.append("result")
            case .finish(let reason, _, _): #expect(reason.unified == .toolCalls); sequence.append("finish")
            case .error: Issue.record("Unexpected PTC error")
            default: break
            }
        }
        #expect(sequence == ["program", "child-start", "child-delta", "child-end", "child", "result", "finish"])
    }

    @Test("Stored program and output references follow source server-state policy", arguments: ["stored", "previous", "conversation"])
    func storedReplay(mode: String) async throws {
        let endpoint = try Endpoint(output: [program, programOutput])
        var options: [String: JSONValue] = ["allowedTools": .object(["toolNames": .array([.string("orchestrate")])])]
        if mode == "previous" { options["previousResponseId"] = .string("previous") }
        if mode == "conversation" { options["conversation"] = .string("conversation") }
        let generated = try await model(endpoint).doGenerate(options: .init(prompt: [.assistant(content: [
            .toolCall(.init(toolCallId: "parent", toolName: "orchestrate", input: .object(["code": .string(code), "fingerprint": .string(fingerprint)]), providerExecuted: true, providerOptions: ["openai": ["itemId": .string("program_item")]])),
            .toolResult(.init(toolCallId: "parent", toolName: "orchestrate", output: .json(value: .object(["result": .string("result\n"), "status": .string("incomplete")])), providerOptions: ["openai": ["itemId": .string("output_item")]]))
        ], providerOptions: nil)], tools: tools, providerOptions: ["openai": options]))
        #expect(generated.finishReason.unified == .stop)
        guard case .object(let body)? = await endpoint.value() else { Issue.record("Missing request"); return }
        #expect(body["tool_choice"] == .object(["type": .string("allowed_tools"), "mode": .string("auto"), "tools": .array([.object(["type": .string("programmatic_tool_calling")])])]))
        #expect(body["input"] == .array(mode == "conversation" ? [] : [
            .object(["type": .string("item_reference"), "id": .string("program_item")]), .object(["type": .string("item_reference"), "id": .string("output_item")])
        ]))
    }

    @Test("Program child execution-denied results are refused from either caller source", arguments: [false, true])
    func deniedChild(resultMetadata: Bool) async throws {
        let endpoint = try Endpoint()
        let prompt: LanguageModelV4Prompt = resultMetadata ? [.tool(content: [
            .toolResult(.init(toolCallId: "child", toolName: "lookup", output: .executionDenied(reason: "blocked"), providerOptions: ["openai": ["caller": caller]]))
        ], providerOptions: nil)] : [
            .assistant(content: [.toolCall(.init(toolCallId: "child", toolName: "lookup", input: .object([:]), providerOptions: ["openai": ["caller": caller, "itemId": .string("child_item")]]))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "child", toolName: "lookup", output: .executionDenied(reason: "blocked")))], providerOptions: nil)
        ]
        await #expect(throws: UnsupportedFunctionalityError.self) {
            try await model(endpoint).doGenerate(options: .init(prompt: prompt, tools: tools, providerOptions: ["openai": ["conversation": .string("server")]]))
        }
    }

    @Test("Malformed program replay input and output are typed failures", arguments: [false, true])
    func invalidReplay(output: Bool) async throws {
        let endpoint = try Endpoint()
        let content: LanguageModelV4MessagePart = output
            ? .toolResult(.init(toolCallId: "parent", toolName: "orchestrate", output: .json(value: .object(["result": .null, "status": .string("completed")]))))
            : .toolCall(.init(toolCallId: "parent", toolName: "orchestrate", input: .object(["code": .string(code), "fingerprint": .null]), providerExecuted: true))
        await #expect(throws: TypeValidationError.self) {
            try await model(endpoint).doGenerate(options: .init(prompt: [.assistant(content: [content], providerOptions: nil)], tools: tools, providerOptions: ["openai": ["store": .bool(false)]]))
        }
    }
}
