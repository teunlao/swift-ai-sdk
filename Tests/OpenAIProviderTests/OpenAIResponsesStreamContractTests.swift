import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses chunk boundary contracts")
struct OpenAIResponsesStreamContractTests {
    private let start: JSONValue = .object([
        "type": .string("response.output_item.added"), "output_index": .number(0),
        "item": .object(["type": .string("message"), "id": .string("msg")])
    ])
    private let completed: JSONValue = .object(["type": .string("response.completed"), "response": .object([:])])

    private func open(_ frames: [JSONValue]) async throws -> LanguageModelV4StreamResult {
        var body = Data()
        for frame in frames {
            body.append(Data("data: ".utf8))
            body.append(try JSONEncoder().encode(frame))
            body.append(Data("\n\n".utf8))
        }
        body.append(Data("data: [DONE]\n\n".utf8))
        let data = body
        let provider = try createOpenAI(settings: .init(apiKey: "test", fetch: { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]
            )!)
        }))
        return try await provider.responses("gpt-4.1").doStream(options: .init(prompt: [], includeRawChunks: true))
    }
    private func collect(_ frames: [JSONValue]) async throws -> [LanguageModelV4StreamPart] {
        let result = try await open(frames)
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        return parts
    }
    private func unknown(_ item: Bool) -> JSONValue {
        item
            ? .object(["type": .string("response.output_item.added"), "output_index": .string("future"), "item": .object(["type": .string("future_item"), "extra": .bool(true)])])
            : .object(["type": .string("response.future_event"), "extra": .null])
    }

    @Test("Malformed known frames emit raw then typed error and an error finish", arguments: [
        JSONValue.object(["type": .string("response.output_text.delta"), "item_id": .string("msg"), "delta": .number(4)]),
        .object(["type": .string("response.output_item.added"), "output_index": .number(1), "item": .object(["type": .string("message")])]),
        .object(["type": .string("response.output_item.added"), "output_index": .number(1), "item": .string("invalid")]),
        .object(["type": .string("response.completed"), "response": .object(["usage": .object(["input_tokens": .number(1.5), "output_tokens": .number(1)])])])
    ])
    func malformedKnown(frame: JSONValue) async throws {
        let parts = try await collect([start, frame, completed])
        let rawIndex = try #require(parts.firstIndex { if case .raw(let raw) = $0 { return raw == frame }; return false })
        let errorIndex = try #require(parts.firstIndex { if case .error(.error(let error)) = $0 { return error is TypeValidationError }; return false })
        let finishIndex = try #require(parts.firstIndex { if case .finish = $0 { return true }; return false })
        #expect(rawIndex < errorIndex && errorIndex < finishIndex)
        guard case .finish(let reason, _, _) = parts[finishIndex] else { return }
        #expect(reason.unified == .error)
    }

    @Test("Genuine unknown events and items keep raw data and allow completion", arguments: [false, true])
    func unknownFallback(item: Bool) async throws {
        let frame = unknown(item)
        let parts = try await collect([frame, completed])
        #expect(parts.contains { if case .raw(let raw) = $0 { return raw == frame }; return false })
        #expect(!parts.contains { if case .error = $0 { return true }; return false })
        guard case .finish(let reason, _, _)? = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .stop)
    }

    @Test("Unknown frames cannot hide a pre-output provider error", arguments: [false, true])
    func unknownDoesNotOpenOutput(item: Bool) async throws {
        let error: JSONValue = .object(["type": .string("error"), "sequence_number": .number(1), "code": .string("rate_limit_exceeded"), "message": .string("Limited")])
        do {
            _ = try await open([unknown(item), error])
            Issue.record("Expected pre-output API error")
        } catch let error as APICallError {
            #expect(error.statusCode == 429)
            #expect(error.isRetryable == true)
        }
    }

    @Test("Error projection preserves null versus absent parameters", arguments: [true, false])
    func projectedError(withNull: Bool) async throws {
        for failed in [false, true] {
            var projected: [String: JSONValue]
            if failed {
                var response: [String: JSONValue] = ["error": .object(["code": .string("server_error"), "message": .string("Late failure")])]
                if withNull { response["incomplete_details"] = .null; response["service_tier"] = .null }
                projected = ["type": .string("response.failed"), "sequence_number": .number(2), "response": .object(response)]
            } else {
                projected = ["type": .string("error"), "sequence_number": .number(2), "code": .string("server_error"), "message": .string("Late failure")]
                if withNull { projected["param"] = .null }
            }
            var raw = projected
            raw["future"] = .object(["kept": .bool(true)])
            let parts = try await collect([start, .object(raw), completed])
            let error = try #require(parts.compactMap { part -> ProviderStreamError? in
                if case .error(.providerStreamError(let value)) = part { return value }; return nil
            }.first)
            #expect(error.data == .object(projected))
            #expect(error.statusCode == 500)
            #expect(parts.contains { if case .raw(let value) = $0 { return value == .object(raw) }; return false })
            guard case .finish(let reason, _, _)? = parts.last else { Issue.record("Missing finish"); return }
            #expect(reason.unified == .error)
        }
    }

    @Test("Completion usage retains future fields and optional detail presence", arguments: ["response.completed", "response.incomplete"])
    func rawUsage(event: String) async throws {
        var usage: [String: JSONValue] = [
            "input_tokens": .number(5), "output_tokens": .number(3), "total_tokens": .number(8.5),
            "future_meter": .object(["units": .number(0.25)]),
            "output_tokens_details": .object(["reasoning_tokens": .number(1), "orchestration_output_tokens": .number(0.5), "extra": .null])
        ]
        if event == "response.incomplete" { usage["input_tokens_details"] = .null }
        let frame: JSONValue = .object(["type": .string(event), "response": .object([
            "usage": .object(usage), "incomplete_details": event == "response.incomplete" ? .object(["reason": .string("max_output_tokens")]) : .null
        ])])
        let parts = try await collect([start, frame])
        guard case .finish(let reason, let result, _)? = parts.last else { Issue.record("Missing finish"); return }
        #expect(result.raw == .object(usage))
        #expect(result.inputTokens.noCache == 5)
        #expect(result.outputTokens.text == 2)
        #expect(reason.unified == (event == "response.completed" ? .stop : .length))
    }

    @Test("Failed web searches stream provider tool errors", arguments: ["failed", "incomplete"])
    func webSearchFailure(status: String) async throws {
        let parts = try await collect([
            .object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": .object([
                "type": .string("web_search_call"), "id": .string("search"), "status": .string("in_progress")
            ])]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object([
                "type": .string("web_search_call"), "id": .string("search"), "status": .string(status), "action": .null
            ])]), completed
        ])
        let toolResult = try #require(parts.compactMap { part -> LanguageModelV4ToolResult? in
            if case .toolResult(let value) = part { return value }; return nil
        }.first)
        #expect(toolResult.toolCallId == "search")
        #expect(toolResult.toolName == "web_search")
        #expect(toolResult.isError == true)
        #expect(toolResult.result == .object(["status": .string(status)]))
    }

    @Test("Numeric tool indices remain independent without truncation or caps")
    func numberToolIndices() async throws {
        let calls: [(Double, String)] = [(1.25, "first"), (1.75, "second"), (1e20, "wide")]
        var frames: [JSONValue] = []
        for (index, id) in calls {
            frames.append(.object(["type": .string("response.output_item.added"), "output_index": .number(index), "item": .object([
                "type": .string("function_call"), "id": .string("item-\(id)"), "call_id": .string(id), "name": .string("lookup"), "arguments": .string("")
            ])]))
        }
        for (index, id) in calls {
            let arguments = "{\"name\":\"\(id)\"}"
            frames.append(.object(["type": .string("response.function_call_arguments.delta"), "item_id": .string("item-\(id)"), "output_index": .number(index), "delta": .string(arguments)]))
            frames.append(.object(["type": .string("response.output_item.done"), "output_index": .number(index), "item": .object([
                "type": .string("function_call"), "id": .string("item-\(id)"), "call_id": .string(id), "name": .string("lookup"), "arguments": .string(arguments), "status": .string("completed")
            ])]))
        }
        frames.append(completed)
        let parts = try await collect(frames)
        for (_, id) in calls {
            #expect(parts.contains { if case .toolInputDelta(let callId, let delta, _) = $0 { return callId == id && delta == "{\"name\":\"\(id)\"}" }; return false })
            #expect(parts.contains { if case .toolCall(let call) = $0 { return call.toolCallId == id && call.input == "{\"name\":\"\(id)\"}" }; return false })
        }
        guard case .finish(let reason, _, _)? = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .toolCalls)
    }

    @Test("Sparse reasoning indices retain ECMAScript number IDs", arguments: [(1.5, "1.5"), (1e20, "100000000000000000000"), (1e21, "1e+21")])
    func sparseReasoningIndex(index: Double, suffix: String) async throws {
        let added: JSONValue = .object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": .object(["type": .string("reasoning"), "id": .string("rs")])])
        let summary: JSONValue = .object(["type": .string("response.reasoning_summary_part.added"), "item_id": .string("rs"), "summary_index": .number(index)])
        let delta: JSONValue = .object(["type": .string("response.reasoning_summary_text.delta"), "item_id": .string("rs"), "summary_index": .number(index), "delta": .string("Thought")])
        let done: JSONValue = .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object(["type": .string("reasoning"), "id": .string("rs")])])
        let parts = try await collect([added, summary, delta, done, completed])
        #expect(parts.contains { if case .reasoningDelta(let id, let text, _) = $0 { return id == "rs:\(suffix)" && text == "Thought" }; return false })
        #expect(parts.contains { if case .reasoningEnd(let id, _) = $0 { return id == "rs:\(suffix)" }; return false })
    }

    @Test("Reasoning end events follow ECMAScript property enumeration order")
    func reasoningKeyOrder() async throws {
        var frames: [JSONValue] = [.object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": .object(["type": .string("reasoning"), "id": .string("rs")])])]
        for index in [4_294_967_295.0, 1.75, 2, 1.25, 1, 4_294_967_294] {
            frames.append(.object(["type": .string("response.reasoning_summary_part.added"), "item_id": .string("rs"), "summary_index": .number(index)]))
        }
        frames.append(.object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object(["type": .string("reasoning"), "id": .string("rs")])]))
        frames.append(completed)
        let parts = try await collect(frames)
        let ids = parts.compactMap { part -> String? in if case .reasoningEnd(let id, _) = part { return id }; return nil }
        #expect(ids == ["rs:0", "rs:1", "rs:2", "rs:4294967294", "rs:4294967295", "rs:1.75", "rs:1.25"])
    }
}
