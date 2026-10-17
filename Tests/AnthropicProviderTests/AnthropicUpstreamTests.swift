import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

private actor UpstreamRequest {
    var value: URLRequest?
    func store(_ request: URLRequest) { value = request }
    func body() throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: value?.httpBody ?? Data())
    }
}

private func upstreamFixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures").appendingPathComponent(name)
    return try Data(contentsOf: url)
}

private func upstreamModel(
    _ id: String = "claude-opus-5-5",
    response: Data,
    stream: Bool = false,
    capture: UpstreamRequest = UpstreamRequest()
) -> AnthropicMessagesLanguageModel {
    createAnthropic(settings: .init(apiKey: "test-key", fetch: { request in
        await capture.store(request)
        return FetchResponse(body: .data(response), urlResponse: HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": stream ? "text/event-stream" : "application/json"]
        )!)
    })).messages(id)
}

private func upstreamParts(_ model: AnthropicMessagesLanguageModel, tools: [LanguageModelV4Tool]? = nil) async throws -> [LanguageModelV4StreamPart] {
    let result = try await model.doStream(options: .init(prompt: [], tools: tools))
    var parts: [LanguageModelV4StreamPart] = []
    for try await part in result.stream { parts.append(part) }
    return parts
}

private func upstreamSSE(_ events: [[String: JSONValue]]) throws -> Data {
    var data = Data()
    for event in events {
        data.append(Data("data: ".utf8))
        data.append(try JSONEncoder().encode(event))
        data.append(Data("\n\n".utf8))
    }
    return data
}

private let upstreamComputer: LanguageModelV4Tool = .provider(.init(id: "anthropic.computer_toolset_20260801", name: "desktop", args: [:]))

@Suite("Anthropic upstream public contracts")
struct AnthropicUpstreamTests {
    @Test("Inline application files resolve their PDF media type before validation", arguments: [false, true])
    func inlinePDF(_ base64: Bool) async throws {
        let capture = UpstreamRequest()
        let pdf = Data("%PDF-1.7\n".utf8)
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"), capture: capture)
        _ = try await model.doGenerate(options: .init(prompt: [
            .user(content: [.file(.init(data: base64 ? .base64(pdf.base64EncodedString()) : .data(pdf), mediaType: "application/*"))], providerOptions: nil)
        ]))
        let body = try await capture.body()
        guard case .array(let messages)? = body["messages"],
              case .object(let message)? = messages.first,
              case .array(let content)? = message["content"],
              case .object(let document)? = content.first else {
            Issue.record("Expected document content")
            return
        }
        #expect(document["type"] == .string("document"))
        #expect(document["source"] == .object(["type": .string("base64"), "media_type": .string("application/pdf"), "data": .string(pdf.base64EncodedString())]))
        let request = try #require(await capture.value)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta")?.split(separator: ",").contains("pdfs-2024-09-25") == true)
    }

    @Test("Invalid integer usage stays raw while generation and streaming succeed", arguments: [false, true])
    func unknownUsage(_ streaming: Bool) async throws {
        let raw: [String: JSONValue] = [
            "input_tokens": .number(1.5), "output_tokens": .number(1e100),
            "cache_creation_input_tokens": .number(2.5), "cache_read_input_tokens": .number(1e100),
            "output_tokens_details": .object(["thinking_tokens": .number(3.5)]),
            "cache_creation": .object(["ephemeral_5m_input_tokens": .number(1e100)]),
            "iterations": .array([.object(["type": .string("message"), "input_tokens": .number(1.5), "output_tokens": .number(1e100)])])
        ]
        let usage: LanguageModelV4Usage
        if streaming {
            let data = try upstreamSSE([
                ["type": .string("message_start"), "message": .object(["id": .string("msg"), "usage": .object(raw)])],
                ["type": .string("message_delta"), "delta": .object(["stop_reason": .string("end_turn")]), "usage": .object(raw)],
                ["type": .string("message_stop")]
            ])
            let parts = try await upstreamParts(upstreamModel(response: data, stream: true))
            guard case .finish(_, let value, _)? = parts.last else { Issue.record("Expected finish"); return }
            usage = value
        } else {
            let data = try JSONEncoder().encode(JSONValue.object(["type": .string("message"), "content": .array([]), "stop_reason": .string("end_turn"), "usage": .object(raw)]))
            usage = try await upstreamModel(response: data).doGenerate(options: .init(prompt: [])).usage
        }
        #expect(usage.inputTokens.total == nil)
        #expect(usage.inputTokens.noCache == nil)
        #expect(usage.inputTokens.cacheRead == nil)
        #expect(usage.inputTokens.cacheWrite == nil)
        #expect(usage.outputTokens.total == nil)
        #expect(usage.outputTokens.reasoning == nil)
        #expect(usage.raw == .object(raw))
    }

    @Test("Token budgets reject fractional and unrepresentable values", arguments: [1.5, 1e100])
    func invalidThinkingBudget(_ budget: Double) async throws {
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"))
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: [], providerOptions: ["anthropic": ["thinking": .object(["type": .string("enabled"), "budgetTokens": .number(budget)])]]))
        }
    }

    @Test("Context token and turn counts reject fractional values", arguments: [
        ("clear_tool_uses_20250919", "trigger", "input_tokens"),
        ("clear_tool_uses_20250919", "keep", "tool_uses"),
        ("clear_tool_uses_20250919", "clearAtLeast", "input_tokens"),
        ("clear_thinking_20251015", "keep", "thinking_turns"),
        ("compact_20260112", "trigger", "input_tokens")
    ])
    func invalidContextCount(_ edit: String, _ field: String, _ type: String) async throws {
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"))
        let context: JSONValue = .object(["edits": .array([.object(["type": .string(edit), field: .object(["type": .string(type), "value": .number(1.5)])])])])
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: [], providerOptions: ["anthropic": ["contextManagement": context]]))
        }
    }

    @Test("Tool limits and display dimensions reject fractional values", arguments: ["anthropic.web_fetch_20260318", "anthropic.web_search_20260318", "anthropic.advisor_20260301", "anthropic.text_editor_20250728", "anthropic.computer_20251124"])
    func invalidToolCount(_ id: String) async throws {
        let args: [String: JSONValue]
        switch id {
        case "anthropic.web_fetch_20260318": args = ["maxContentTokens": .number(1.5)]
        case "anthropic.web_search_20260318": args = ["maxUses": .number(1.5)]
        case "anthropic.advisor_20260301": args = ["model": .string("claude-opus-5-5"), "maxUses": .number(1.5)]
        case "anthropic.text_editor_20250728": args = ["maxCharacters": .number(1.5)]
        default: args = ["displayWidthPx": .number(1.5), "displayHeightPx": .number(768)]
        }
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"))
        await #expect(throws: TypeValidationError.self) {
            _ = try await model.doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: id, name: "tool", args: args))]))
        }
    }

    @Test("Malformed integer tool results are rejected at the Messages boundary", arguments: [1.5, 1e100])
    func invalidToolResultCount(_ count: Double) async throws {
        let data = try JSONEncoder().encode(JSONValue.object([
            "type": .string("message"), "content": .array([.object([
                "type": .string("code_execution_tool_result"), "tool_use_id": .string("server"),
                "content": .object(["type": .string("code_execution_result"), "stdout": .string(""), "stderr": .string(""), "return_code": .number(count)])
            ])]), "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)])
        ]))
        await #expect(throws: APICallError.self) {
            _ = try await upstreamModel(response: data).doGenerate(options: .init(prompt: []))
        }
    }

    @Test("Large output budgets are capped without integer conversion traps")
    func largeOutputBudget() async throws {
        let capture = UpstreamRequest()
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"), capture: capture)
        let result = try await model.doGenerate(options: .init(prompt: [], maxOutputTokens: Int.max))
        #expect(try await capture.body()["max_tokens"] == .number(128000))
        #expect(result.warnings.contains { warning in
            if case .unsupported(let feature, _) = warning { return feature == "maxOutputTokens" }
            return false
        })
    }

    @Test("Usage totals and reasoning subtraction cannot overflow")
    func usageOverflow() async throws {
        let raw: [String: JSONValue] = [
            "input_tokens": .number(9e18), "cache_read_input_tokens": .number(9e18),
            "output_tokens": .number(9e18), "output_tokens_details": .object(["thinking_tokens": .number(-9e18)])
        ]
        let data = try JSONEncoder().encode(JSONValue.object(["type": .string("message"), "content": .array([]), "usage": .object(raw)]))
        let usage = try await upstreamModel(response: data).doGenerate(options: .init(prompt: [])).usage
        #expect(usage.inputTokens.total == nil)
        #expect(usage.inputTokens.noCache == 9_000_000_000_000_000_000)
        #expect(usage.outputTokens.total == 9_000_000_000_000_000_000)
        #expect(usage.outputTokens.text == nil)
        #expect(usage.raw == .object(raw))
    }

    @Test(arguments: ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])
    func disabledThinkingCapabilities(_ id: String) async throws {
        let capture = UpstreamRequest()
        let model = upstreamModel(id, response: try upstreamFixture("upstream-response.json"), capture: capture)
        let result = try await model.doGenerate(options: .init(prompt: [], providerOptions: ["anthropic": [
            "thinking": .object(["type": .string("disabled")]), "effort": .string("max")
        ]]))
        let body = try await capture.body()
        switch id {
        case "claude-opus-5-5":
            #expect(body["thinking"] == nil)
            #expect(body["output_config"] == .object(["effort": .string("max")]))
        case "claude-sonnet-5-5":
            #expect(body["thinking"] == .object(["type": .string("between_tools")]))
            #expect(body["output_config"] == .object(["effort": .string("high")]))
        default:
            #expect(body["thinking"] == .object(["type": .string("disabled")]))
            #expect(body["output_config"] == .object(["effort": .string("high")]))
        }
        #expect(body["max_tokens"] == .number(128000))
        #expect(!result.warnings.isEmpty)
    }

    @Test
    func bindingCompactionFallbacksAndCustomSkills() async throws {
        let capture = UpstreamRequest()
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"), capture: capture)
        _ = try await model.doGenerate(options: .init(prompt: [], providerOptions: ["anthropic": [
            "thinking": .object(["blockBinding": .object(["prefixMismatchBehavior": .string("drop_block")])]),
            "fallbacks": .string("default"), "serviceTier": .string("standard_only"),
            "compaction": .object(["type": .string("summarize"), "instructions": .string("Keep tool state")]),
            "safeguards": .array([.object(["type": .string("dangerous_tool_use"), "classifierContext": .object(["mode": .string("safe")])])]),
            "container": .object(["skills": .array([.object(["type": .string("custom"), "providerReference": .object(["anthropic": .string("skill_custom")])])])])
        ]]))
        let body = try await capture.body()
        #expect(body["thinking"] == .object(["block_binding": .object(["prefix_mismatch_behavior": .string("drop_block")])]))
        #expect(body["fallbacks"] == .string("default"))
        #expect(body["service_tier"] == .string("standard_only"))
        #expect(body["container"] == .object(["skills": .array([.object(["type": .string("custom"), "skill_id": .string("skill_custom")])])]))
        #expect(body["compaction"] == .object(["type": .string("summarize"), "instructions": .string("Keep tool state")]))
        #expect(body["safeguards"] == .array([.object(["type": .string("dangerous_tool_use"), "classifier_context": .object(["mode": .string("safe")])])]))
        let request = try #require(await capture.value)
        let betas = Set((request.value(forHTTPHeaderField: "anthropic-beta") ?? "").split(separator: ",").map(String.init))
        #expect(betas.isSuperset(of: ["thinking-binding-controls-2026-08-01", "server-side-fallback-2026-07-01", "compact-2026-09-04", "dangerous-tool-use-2026-09-03", "skills-2025-10-02"]))
    }

    @Test
    func parsedContentCitationsUsageAndMetadata() async throws {
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"))
        let result = try await model.doGenerate(options: .init(prompt: [], tools: [upstreamComputer]))
        #expect(result.usage.inputTokens.total == 50)
        #expect(result.usage.outputTokens.total == 50)
        #expect(result.usage.outputTokens.reasoning == 20)
        #expect(result.usage.outputTokens.text == 30)
        let text = try #require(result.content.compactMap { if case .text(let text) = $0, text.text == "The article explains it." { return text }; return nil }.first)
        #expect(text.citations?.count == 2)
        if case .url(let id, let url, let title, _) = text.citations?.first?.source {
            #expect(id == "https://example.com/article")
            #expect(url == id)
            #expect(title == nil)
        } else { Issue.record("Expected a stable URL citation") }
        if case .document(let id, let mediaType, let title, _, _) = text.citations?.last?.source {
            #expect(id == "file_quote")
            #expect(mediaType == "text/plain")
            #expect(title == "Document 3")
        } else { Issue.record("Expected a referenced document citation") }
        let sources = result.content.compactMap { if case .source(let source) = $0 { return source }; return nil }
        #expect(sources.count == 1)
        let call = try #require(result.content.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }.first)
        #expect(call.toolName == "desktop")
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8)) == .object(["action": .string("left_click"), "coordinate": .array([.number(10), .number(20)])]))
        #expect(call.providerMetadata?["anthropic"]?["toolsetName"] == .string("computer"))
        let metadata = try #require(result.providerMetadata?["anthropic"])
        #expect(metadata["usage"] == .object(["input_tokens": .number(40), "output_tokens": .number(50), "output_tokens_details": .object(["thinking_tokens": .number(20)]), "cache_creation_input_tokens": .number(3), "cache_read_input_tokens": .number(7), "server_tool_use": .object(["web_search_requests": .number(1)])]))
        #expect(metadata["inputTransformations"] != nil)
        #expect(metadata["safeguardResults"] != nil)
        let customKinds = result.content.compactMap { if case .custom(let custom) = $0 { return custom.kind }; return nil }
        #expect(customKinds == ["anthropic.fallback", "anthropic.container_upload"])
        let summary = try #require(result.content.compactMap { if case .text(let text) = $0, text.text == "Conversation summary" { return text }; return nil }.first)
        #expect(summary.providerMetadata?["anthropic"]?["signature"] == .string("signed-summary"))
        let advice = try #require(result.content.compactMap { if case .toolResult(let result) = $0, result.toolCallId == "advisor_1" { return result }; return nil }.first)
        #expect(advice.result == .object(["type": .string("advisor_result"), "text": .string("Advice"), "stopReason": .string("end_turn")]))
    }

    @Test
    func streamingSignedCompactionToolsetAndCitationOrder() async throws {
        let model = upstreamModel(response: try upstreamFixture("upstream-stream.txt"), stream: true)
        let parts = try await upstreamParts(model, tools: [upstreamComputer])
        #expect(parts[1] == .responseMetadata(id: "msg_stream", modelId: "claude-opus-5-5", timestamp: nil))
        if case .custom(let custom) = parts[2] { #expect(custom.kind == "anthropic.message_start") }
        else { Issue.record("Missing message_start metadata") }
        #expect(parts[3] == .textStart(id: "0", providerMetadata: ["anthropic": ["type": .string("compaction"), "signature": .string("signed-summary")]]))
        #expect(parts[4] == .textDelta(id: "0", delta: "Conversation summary", providerMetadata: nil))
        let deltas = parts.compactMap { part -> String? in if case .toolInputDelta(let id, let delta, _) = part, id == "computer_1" { return delta }; return nil }
        #expect(deltas.count == 1)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(try #require(deltas.first).utf8)) == .object(["action": .string("left_click"), "coordinate": .array([.number(10), .number(20)])]))
        let end = try #require(parts.first { if case .textEnd(let id, _, _) = $0 { return id == "3" }; return false })
        if case .textEnd(_, let metadata, let citations) = end {
            #expect(citations?.first?.citedText == "quote")
            #expect(metadata?["anthropic"]?["citations"] != nil)
        }
        if case .source(.url(_, let url, _, _)) = parts[parts.count - 2] { #expect(url == "https://example.com/article") }
        else { Issue.record("Citation-only sources must precede finish") }
        if case .finish(_, let usage, let metadata) = parts.last {
            #expect(usage.outputTokens.reasoning == 20)
            #expect(usage.outputTokens.text == 30)
            #expect(metadata?["anthropic"]?["inputTransformations"] != nil)
            #expect(metadata?["anthropic"]?["safeguardResults"] != nil)
        } else { Issue.record("Missing finish") }
    }

    @Test(arguments: ["object", "omitted", "null"])
    func firstAndLaterProviderErrorsKeepRetryMetadata(dataMode: String) async throws {
        var payload: [String: JSONValue] = [
            "type": .string("rate_limit_error"), "message": .string("Busy"), "code": .number(7),
            "statusCode": .null, "isRetryable": .null
        ]
        let expectedData: JSONValue
        switch dataMode {
        case "object":
            expectedData = .object(["retryAfter": .number(2)])
            payload["data"] = expectedData
        case "null":
            expectedData = .null
            payload["data"] = expectedData
        default:
            expectedData = .object(payload)
        }
        let error: [String: JSONValue] = ["type": .string("error"), "error": .object(payload)]
        let first = upstreamModel(response: try upstreamSSE([error]), stream: true)
        do {
            _ = try await first.doStream(options: .init(prompt: []))
            Issue.record("Expected first-event APICallError")
        } catch let failure as APICallError {
            #expect(failure.statusCode == 429)
            #expect(failure.isRetryable)
            let body = try #require(failure.responseBody)
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)) == expectedData)
        }
        let start: [String: JSONValue] = ["type": .string("message_start"), "message": .object(["id": .string("msg_error"), "model": .string("claude-opus-5-5"), "usage": .object(["input_tokens": .number(1)])])]
        let later = upstreamModel(response: try upstreamSSE([start, error]), stream: true)
        let parts = try await upstreamParts(later)
        if case .error(.providerStreamError(let failure)) = parts.last {
            #expect(failure.code == .number(7))
            #expect(failure.statusCode == 429)
            #expect(failure.isRetryable == true)
            #expect(failure.data == expectedData)
        } else { Issue.record("Expected typed mid-stream provider error") }
    }

    @Test(arguments: [
        ["thinking": JSONValue.null],
        ["fallbacks": .array([.object(["model": .string("claude-sonnet-5"), "max_tokens": .number(0)])])],
        ["compaction": .object(["type": .string("summarize")]), "contextManagement": .object(["edits": .array([])])],
    ])
    func invalidProviderOptionsHaveTypedFailures(_ options: [String: JSONValue]) async throws {
        let model = upstreamModel(response: try upstreamFixture("upstream-response.json"))
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(prompt: [], providerOptions: ["anthropic": options]))
        }
    }

    @Test
    func malformedProviderToolResultsFailAtTheResponseBoundary() async throws {
        var response = try JSONDecoder().decode([String: JSONValue].self, from: upstreamFixture("upstream-response.json"))
        response["content"] = .array([.object([
            "type": .string("web_search_tool_result"), "tool_use_id": .string("search_1"),
            "content": .array([.object(["type": .string("web_search_result"), "url": .string("https://example.com"), "encrypted_content": .string("encrypted")])])
        ])])
        let model = upstreamModel(response: try JSONEncoder().encode(response))
        do {
            _ = try await model.doGenerate(options: .init(prompt: []))
            Issue.record("Expected invalid response rejection")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.cause is TypeValidationError)
        }
    }

    @Test
    func duplicateMessageStartsDoNotDuplicateMetadata() async throws {
        let start: [String: JSONValue] = ["type": .string("message_start"), "message": .object(["id": .string("msg_batch"), "model": .string("claude-opus-5-5"), "usage": .object(["input_tokens": .number(1)])])]
        let model = upstreamModel(response: try upstreamSSE([start, start, ["type": .string("message_stop")]]), stream: true)
        let parts = try await upstreamParts(model)
        let starts = parts.compactMap { if case .custom(let custom) = $0 { return custom.kind }; return nil }
        #expect(starts == ["anthropic.message_start"])
        #expect(parts.count == 4)
    }
}
