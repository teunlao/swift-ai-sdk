import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses computer wire contracts")
struct OpenAIResponsesComputerTests {
    private actor Endpoint {
        let body: Data
        let streaming: Bool
        var request: JSONValue?
        init(_ value: JSONValue) throws { body = try JSONEncoder().encode(value); streaming = false }
        init(frames: [JSONValue]) throws {
            body = Data(try frames.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
            streaming = true
        }
        func fetch(_ request: URLRequest) throws -> FetchResponse {
            self.request = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            return FetchResponse(body: .data(body), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!)
        }
        func value() -> JSONValue? { request }
    }
    private var tools: [LanguageModelV4Tool] {
        let tool = openaiTools.computer()
        return [.provider(.init(id: tool.id!, name: "desktop", args: tool.args ?? [:]))]
    }
    private func model(_ endpoint: Endpoint) throws -> OpenAIResponsesLanguageModel {
        try createOpenAI(settings: .init(apiKey: "test", fetch: { try await endpoint.fetch($0) })).responses("gpt-6")
    }
    private let wireCall: JSONValue = .object([
        "type": .string("computer_call"), "id": .string("cu"), "call_id": .string("call"), "status": .string("completed"),
        "actions": .array([
            .object(["type": .string("scroll"), "x": .number(1.5), "y": .number(1e20), "scroll_x": .number(-0.25), "scroll_y": .number(2.75), "keys": .null]),
            .object(["type": .string("drag"), "path": .array([.object(["x": .number(2.5), "y": .number(-3.5), "extra": .bool(true)])]), "keys": .array([])])
        ]),
        "pending_safety_checks": .array([.object(["id": .string("check"), "code": .null, "message": .string("review"), "extra": .bool(true)])])
    ])
    private let expectedInput: JSONValue = .object([
        "actions": .array([
            .object(["type": .string("scroll"), "x": .number(1.5), "y": .number(1e20), "scrollX": .number(-0.25), "scrollY": .number(2.75)]),
            .object(["type": .string("drag"), "path": .array([.object(["x": .number(2.5), "y": .number(-3.5)])]), "keys": .array([])])
        ]),
        "pendingSafetyChecks": .array([.object(["id": .string("check"), "message": .string("review")])]), "status": .string("completed")
    ])
    private let result: JSONValue = .object([
        "output": .object(["type": .string("computer_screenshot"), "imageUrl": .string("https://media.test/screen.png"), "fileId": .string("file_screen"), "detail": .string("original"), "extra": .bool(true)]),
        "acknowledgedSafetyChecks": .array([.object(["id": .string("check"), "code": .string(""), "extra": .bool(true)])])
    ])

    @Test("Computer generation maps actions and tool choice and round-trips screenshot history")
    func generateAndReplay() async throws {
        let first = try Endpoint(.object(["output": .array([wireCall])]))
        let generated = try await model(first).doGenerate(options: .init(prompt: [], tools: tools, toolChoice: .tool(toolName: "desktop")))
        guard case .object(let request)? = await first.value() else { Issue.record("Missing request"); return }
        #expect(request["tools"] == .array([.object(["type": .string("computer")])]))
        #expect(request["tool_choice"] == .object(["type": .string("computer")]))
        #expect(generated.finishReason.unified == .toolCalls)
        let call = try #require(generated.content.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }.first)
        #expect(call.toolCallId == "call")
        #expect(call.toolName == "desktop")
        #expect(call.providerExecuted != true)
        #expect(call.providerMetadata?["openai"]?["itemId"] == .string("cu"))
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8))
        #expect(input == expectedInput)
        let next = try Endpoint(.object(["output": .array([])]))
        _ = try await model(next).doGenerate(options: .init(prompt: [
            .assistant(content: [.toolCall(.init(toolCallId: call.toolCallId, toolName: call.toolName, input: input, providerOptions: call.providerMetadata))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "desktop", output: .json(value: result)))], providerOptions: nil)
        ], tools: tools, providerOptions: ["openai": ["store": .bool(false)]]))
        guard case .object(let replay)? = await next.value(), case .array(let items)? = replay["input"], items.count == 2 else {
            Issue.record("Missing replay items"); return
        }
        guard case .object(let replayCall) = items[0], case .object(let replayOutput) = items[1] else { Issue.record("Invalid replay items"); return }
        #expect(replayCall["type"] == .string("computer_call"))
        #expect(replayCall["id"] == .string("cu"))
        #expect(replayCall["call_id"] == .string("call"))
        #expect(replayCall["actions"] == .array([
            .object(["type": .string("scroll"), "x": .number(1.5), "y": .number(1e20), "scroll_x": .number(-0.25), "scroll_y": .number(2.75)]),
            .object(["type": .string("drag"), "path": .array([.object(["x": .number(2.5), "y": .number(-3.5)])]), "keys": .array([])])
        ]))
        #expect(replayCall["pending_safety_checks"] == .array([.object(["id": .string("check"), "message": .string("review")])]))
        #expect(JSONValue.object(replayOutput) == .object([
            "type": .string("computer_call_output"), "call_id": .string("call"),
            "output": .object(["type": .string("computer_screenshot"), "image_url": .string("https://media.test/screen.png"), "file_id": .string("file_screen"), "detail": .string("original")]),
            "acknowledged_safety_checks": .array([.object(["id": .string("check"), "code": .string("")])])
        ]))
    }

    @Test("Computer stream emits client actions in start-delta-end-call order")
    func streamedActions() async throws {
        let endpoint = try Endpoint(frames: [
            .object(["type": .string("response.output_item.added"), "output_index": .number(0.25), "item": wireCall]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(0.25), "item": wireCall]),
            .object(["type": .string("response.completed"), "response": .object([:])])
        ])
        let response = try await model(endpoint).doStream(options: .init(prompt: [], tools: tools))
        var lifecycle: [String] = []
        var deltas = ""
        for try await part in response.stream {
            switch part {
            case .toolInputStart(let id, let name, _, let executed, _, _, _):
                #expect(id == "call" && name == "desktop" && executed != true); lifecycle.append("start")
            case .toolInputDelta(let id, let delta, _): #expect(id == "call"); deltas += delta; lifecycle.append("delta")
            case .toolInputEnd(let id, _): #expect(id == "call"); lifecycle.append("end")
            case .toolCall(let call):
                #expect(call.toolName == "desktop" && call.toolCallId == "call" && call.providerExecuted != true)
                #expect(call.providerMetadata?["openai"]?["itemId"] == .string("cu"))
                #expect(try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8)) == expectedInput)
                lifecycle.append("call")
            case .toolResult: lifecycle.append("result")
            case .error: Issue.record("Unexpected stream error")
            case .finish(let reason, _, _): #expect(reason.unified == .toolCalls)
            default: break
            }
        }
        #expect(lifecycle == ["start", "delta", "end", "call"])
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(deltas.utf8)) == expectedInput)
    }

    @Test("Computer replay references stored calls and omits calls already in server state", arguments: ["stored", "previous", "conversation"])
    func storedReplay(mode: String) async throws {
        let endpoint = try Endpoint(.object(["output": .array([])]))
        var options: [String: JSONValue] = ["allowedTools": .object(["toolNames": .array([.string("desktop")])])]
        if mode == "previous" { options["previousResponseId"] = .string("previous") }
        if mode == "conversation" { options["conversation"] = .string("conversation") }
        _ = try await model(endpoint).doGenerate(options: .init(prompt: [.assistant(content: [
            .toolCall(.init(toolCallId: "call", toolName: "desktop", input: expectedInput, providerOptions: ["openai": ["itemId": .string("cu")]]))
        ], providerOptions: nil), .tool(content: [
            .toolResult(.init(toolCallId: "call", toolName: "desktop", output: .json(value: .object([
                "output": .object(["type": .string("computer_screenshot"), "fileId": .string("file_screen")])
            ]))))
        ], providerOptions: nil)], tools: tools, providerOptions: ["openai": options]))
        guard case .object(let request)? = await endpoint.value() else { Issue.record("Missing request"); return }
        #expect(request["tool_choice"] == .object(["type": .string("allowed_tools"), "mode": .string("auto"), "tools": .array([.object(["type": .string("computer")])])]))
        let prefix: [JSONValue] = mode == "stored" ? [.object(["type": .string("item_reference"), "id": .string("cu")])] : []
        #expect(request["input"] == .array(prefix + [.object([
            "type": .string("computer_call_output"), "call_id": .string("call"), "output": .object(["type": .string("computer_screenshot"), "file_id": .string("file_screen")])
        ])]))
    }

    @Test("Batched actions take precedence over singular actions and null uses the singular fallback", arguments: [false, true])
    func actionFallback(empty: Bool) async throws {
        let endpoint = try Endpoint(.object(["output": .array([.object([
            "type": .string("computer_call"), "id": .string("cu"), "call_id": .string(""), "status": .string("in_progress"),
            "actions": empty ? .array([]) : .null, "action": .object(["type": .string("screenshot")]), "pending_safety_checks": .null
        ])])]))
        let response = try await model(endpoint).doGenerate(options: .init(prompt: [], tools: tools))
        let call = try #require(response.content.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }.first)
        #expect(call.toolCallId == "")
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8)) == .object([
            "actions": .array(empty ? [] : [.object(["type": .string("screenshot")])]),
            "pendingSafetyChecks": .array([]), "status": .string("in_progress")
        ]))
    }

    @Test("Hosted computer calls preserve provider-executed results", arguments: [false, true])
    func hostedFallback(streaming: Bool) async throws {
        let item: JSONValue = .object(["type": .string("computer_call"), "id": .string("hosted"), "status": .string("incomplete"), "call_id": .null])
        let endpoint = try streaming ? Endpoint(frames: [
            .object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": item]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": item]),
            .object(["type": .string("response.completed"), "response": .object([:])])
        ]) : Endpoint(.object(["output": .array([item])]))
        var calls: [LanguageModelV4ToolCall] = []
        var results: [LanguageModelV4ToolResult] = []
        if streaming {
            let response = try await model(endpoint).doStream(options: .init(prompt: [], tools: tools))
            for try await part in response.stream {
                switch part {
                case .toolInputStart(let id, let name, _, let executed, _, _, _): #expect(id == "hosted" && name == "desktop" && executed != true)
                case .toolCall(let call): calls.append(call)
                case .toolResult(let result): results.append(result)
                case .finish(let reason, _, _): #expect(reason.unified == .stop)
                case .error: Issue.record("Unexpected stream error")
                default: break
                }
            }
        } else {
            let response = try await model(endpoint).doGenerate(options: .init(prompt: [], tools: tools))
            calls = response.content.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }
            results = response.content.compactMap { if case .toolResult(let result) = $0 { return result }; return nil }
            #expect(response.finishReason.unified == .stop)
        }
        #expect(calls.count == 1 && results.count == 1)
        #expect(calls.first?.toolCallId == "hosted" && calls.first?.toolName == "computer_use" && calls.first?.providerExecuted == true)
        #expect(results.first?.result == .object(["type": .string("computer_use_tool_result"), "status": .string("incomplete")]))
    }

    @Test("Denied computer execution follows source scalar output and approval suppression")
    func deniedResult() async throws {
        let endpoint = try Endpoint(.object(["output": .array([])]))
        _ = try await model(endpoint).doGenerate(options: .init(prompt: [.tool(content: [
            .toolResult(.init(toolCallId: "denied", toolName: "desktop", output: .executionDenied(reason: ""))),
            .toolResult(.init(toolCallId: "approval", toolName: "desktop", output: .executionDenied(reason: "blocked", providerOptions: ["openai": ["approvalId": .string("approval")]])))
        ], providerOptions: nil)], tools: tools))
        guard case .object(let request)? = await endpoint.value() else { Issue.record("Missing request"); return }
        #expect(request["input"] == .array([.object(["type": .string("function_call_output"), "call_id": .string("denied"), "output": .string("")])]))
    }

    @Test("Client action optional keys reject null at replay boundary")
    func invalidInput() async throws {
        let endpoint = try Endpoint(.object(["output": .array([])]))
        await #expect(throws: TypeValidationError.self) {
            try await model(endpoint).doGenerate(options: .init(prompt: [.assistant(content: [
                .toolCall(.init(toolCallId: "call", toolName: "desktop", input: .object([
                    "actions": .array([.object(["type": .string("move"), "x": .number(1), "y": .number(2), "keys": .null])]),
                    "pendingSafetyChecks": .array([]), "status": .string("completed")
                ])))
            ], providerOptions: nil)], tools: tools, providerOptions: ["openai": ["store": .bool(false)]]))
        }
    }

    @Test("Malformed screenshots and optional-null safety acknowledgements fail at replay boundary", arguments: [
        JSONValue.object(["output": .object(["type": .string("computer_screenshot")])]),
        .object(["output": .object(["type": .string("computer_screenshot"), "fileId": .string("file"), "detail": .null])]),
        .object(["output": .object(["type": .string("computer_screenshot"), "fileId": .string("file")]), "acknowledgedSafetyChecks": .array([.object(["id": .string("check"), "code": .null])])])
    ])
    func invalidResult(value: JSONValue) async throws {
        let endpoint = try Endpoint(.object(["output": .array([])]))
        await #expect(throws: TypeValidationError.self) {
            try await model(endpoint).doGenerate(options: .init(prompt: [.tool(content: [
                .toolResult(.init(toolCallId: "call", toolName: "desktop", output: .json(value: value)))
            ], providerOptions: nil)], tools: tools))
        }
    }
}
