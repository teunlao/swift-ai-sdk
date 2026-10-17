import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses request contracts")
struct OpenAIResponsesToolContractTests {
    private actor Capture {
        var body: JSONValue?
        func store(_ request: URLRequest) throws {
            body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        }
        func value() -> JSONValue? { body }
    }

    private func provider(_ capture: Capture) throws -> OpenAIProvider {
        try createOpenAI(settings: .init(apiKey: "test", fetch: { request in
            try await capture.store(request)
            return FetchResponse(
                body: .data(Data(#"{"id":"resp_tools","output":[],"usage":{"input_tokens":1,"output_tokens":0}}"#.utf8)),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }))
    }

    @Test("Function schemas normalize together with JSON-encoded scalar history")
    func functionSchemasAndHistory() async throws {
        let capture = Capture()
        let schema: JSONValue = .object([
            "type": .string("string"), "pattern": .string("(?=x)x")
        ])
        let result = try await provider(capture).responses("gpt-6").doGenerate(options: .init(
            prompt: [.tool(content: [
                .toolResult(.init(toolCallId: "text", toolName: "e\u{0301}", output: .text(value: "x"))),
                .toolResult(.init(toolCallId: "denied", toolName: "e\u{0301}", output: .executionDenied(reason: "no"))),
                .toolResult(.init(toolCallId: "ordinary", toolName: "é", output: .text(value: "x")))
            ], providerOptions: nil)],
            tools: [.function(.init(name: "e\u{0301}", inputSchema: schema, providerOptions: ["openai": [
                "outputSchema": schema, "allowedCallers": .array([.string("direct")]), "async": .bool(true)
            ]]))]
        ))
        guard case .object(let body)? = await capture.value(), case .array(let tools)? = body["tools"],
              case .object(let tool)? = tools.first, case .array(let input)? = body["input"] else {
            Issue.record("Missing function request"); return
        }
        #expect(tool["parameters"] == .object(["type": .string("string")]))
        #expect(tool["output_schema"] == .object(["type": .string("string")]))
        #expect(tool["strict"] == .bool(false))
        #expect(tool["async"] == .bool(true))
        #expect(tool["allowed_callers"] == .array([.string("direct")]))
        #expect(input == [
            .object(["type": .string("function_call_output"), "call_id": .string("text"), "output": .string("\"x\"")]),
            .object(["type": .string("function_call_output"), "call_id": .string("denied"), "output": .string("\"no\"")]),
            .object(["type": .string("function_call_output"), "call_id": .string("ordinary"), "output": .string("x")])
        ])
        #expect(result.warnings.count == 2)
    }

    @Test("Async declarations follow model capabilities and preserve false", arguments: ["gpt-5", "gpt-6"])
    func asyncDeclarations(modelId: String) async throws {
        let capture = Capture()
        let result = try await provider(capture).responses(modelId).doGenerate(options: .init(prompt: [], tools: [
            .function(.init(name: "function", inputSchema: .object([:]), providerOptions: ["openai": ["async": .bool(true)]])),
            .provider(.init(id: "openai.custom", name: "custom", args: ["async": .bool(true)])),
            .provider(.init(id: "openai.custom", name: "sync", args: ["async": .bool(false)]))
        ]))
        guard case .object(let body)? = await capture.value(), case .array(let tools)? = body["tools"] else {
            Issue.record("Missing request tools"); return
        }
        for (index, entry) in tools.enumerated() {
            guard case .object(let tool) = entry else { Issue.record("Invalid tool"); return }
            #expect(tool["async"] == (index == 2 ? .bool(false) : modelId == "gpt-6" ? .bool(true) : nil))
        }
        #expect(result.warnings.count == (modelId == "gpt-6" ? 0 : 2))
    }

    @Test("Custom async metadata survives generated and streamed calls", arguments: [false, true])
    func customAsyncMetadata(streaming: Bool) async throws {
        let item: JSONValue = .object(["type": .string("custom_tool_call"), "id": .string("ct"), "call_id": .string("call"), "name": .string("custom"), "input": .string("x"), "async": .bool(false)])
        let payload: Data
        if streaming {
            let frames: [JSONValue] = [
                .object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": item]),
                .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object([
                    "type": .string("custom_tool_call"), "id": .string("ct"), "call_id": .string("call"), "name": .string("custom"), "input": .string("x"), "status": .string("completed")
                ])]),
                .object(["type": .string("response.completed"), "response": .object([:])])
            ]
            payload = Data(try frames.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
        } else {
            payload = try JSONEncoder().encode(JSONValue.object(["output": .array([item])]))
        }
        let provider = try createOpenAI(settings: .init(apiKey: "test", fetch: { request in
            FetchResponse(body: .data(payload), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!)
        }))
        let model = provider.responses("gpt-6")
        let options = LanguageModelV4CallOptions(prompt: [], tools: [.provider(.init(id: "openai.custom", name: "custom", args: [:]))])
        var calls: [LanguageModelV4ToolCall] = []
        if streaming {
            let result = try await model.doStream(options: options)
            var textStart = false
            for try await part in result.stream {
                if case .toolCall(let call) = part { calls.append(call) }
                if case .toolInputStart(_, _, _, _, _, _, let encoding) = part { textStart = encoding == .text }
            }
            #expect(textStart)
        } else {
            let result = try await model.doGenerate(options: options)
            calls = result.content.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }
        }
        #expect(calls.count == 1)
        #expect(calls.first?.input == "\"x\"")
        #expect(calls.first?.providerMetadata?["openai"]?["async"] == .bool(false))
    }

    @Test("Allowed tools resolves provider identities and drops invisible entries")
    func allowedTools() async throws {
        let capture = Capture()
        let tools: [LanguageModelV4Tool] = [
            .provider(.init(id: "openai.web_search", name: "browse", args: [:])),
            .provider(.init(id: "openai.mcp", name: "remote", args: ["serverLabel": .string("docs"), "serverUrl": .string("")])),
            .provider(.init(id: "openai.custom", name: "grammar", args: [:])),
            .function(.init(name: "deferred", inputSchema: .object([:]), providerOptions: ["openai": ["deferLoading": .bool(true)]])),
            .function(.init(name: "nested", inputSchema: .object([:]), providerOptions: ["openai": ["namespace": .object(["name": .string("ns"), "description": .string("")])]]))
        ]
        let result = try await provider(capture).responses("gpt-6").doGenerate(options: .init(
            prompt: [], tools: tools, providerOptions: ["openai": ["allowedTools": .object([
                "toolNames": .array(["web_search", "remote", "grammar", "deferred", "nested"].map(JSONValue.string)), "mode": .string("required")
            ])]]
        ))
        guard case .object(let body)? = await capture.value() else { Issue.record("Missing request"); return }
        #expect(body["tool_choice"] == .object(["type": .string("allowed_tools"), "mode": .string("required"), "tools": .array([
            .object(["type": .string("web_search")]), .object(["type": .string("mcp"), "server_label": .string("docs")]),
            .object(["type": .string("custom"), "name": .string("grammar")])
        ])]))
        #expect(result.warnings.count == 2)
        await #expect(throws: UnsupportedFunctionalityError.self) {
            try await provider(capture).responses("gpt-6").doGenerate(options: .init(
                prompt: [], tools: tools, providerOptions: ["openai": ["allowedTools": .object(["toolNames": .array([.string("deferred")])])]]
            ))
        }
    }

    @Test("Allowed tool aliases preserve direct names and report ambiguous or unknown entries")
    func allowedToolAliases() async throws {
        let capture = Capture()
        let result = try await provider(capture).responses("gpt-6").doGenerate(options: .init(prompt: [], tools: [
            .provider(.init(id: "openai.mcp", name: "first", args: ["serverLabel": .string("a"), "serverUrl": .string("")])),
            .provider(.init(id: "openai.mcp", name: "second", args: ["serverLabel": .string("b"), "serverUrl": .string("")])),
            .provider(.init(id: "openai.web_search", name: "browse", args: [:])),
            .function(.init(name: "web_search", inputSchema: .object([:]))),
            .provider(.init(id: "openai.tool_search", name: "finder", args: [:]))
        ], providerOptions: ["openai": ["allowedTools": .object(["toolNames": .array(["mcp", "web_search", "finder", "first", "unknown"].map(JSONValue.string))])]]))
        guard case .object(let body)? = await capture.value() else { Issue.record("Missing request"); return }
        #expect(body["tool_choice"] == .object(["type": .string("allowed_tools"), "mode": .string("auto"), "tools": .array([
            .object(["type": .string("function"), "name": .string("web_search")]),
            .object(["type": .string("mcp"), "server_label": .string("a")]),
            .object(["type": .string("function"), "name": .string("unknown")])
        ])]))
        #expect(result.warnings.count == 4)
    }

    @Test("Tool search SDK names use literal byte identity")
    func requestLiteralToolSearch() async throws {
        let capture = Capture()
        _ = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(prompt: [
            .assistant(content: [.toolCall(.init(toolCallId: "call", toolName: "e\u{0301}", input: .object(["value": .string("ok")])))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "e\u{0301}", output: .json(value: .number(7))))], providerOptions: nil)
        ], tools: [
            .provider(.init(id: "openai.tool_search", name: "é", args: [:])),
            .function(.init(name: "e\u{0301}", inputSchema: .object(["type": .string("object")])))
        ]))
        guard case .object(let body)? = await capture.value(), case .array(let input)? = body["input"] else {
            Issue.record("Missing input"); return
        }
        #expect(input == [
            .object(["type": .string("function_call"), "call_id": .string("call"), "name": .string("e\u{0301}"), "arguments": .string("{\"value\":\"ok\"}")]),
            .object(["type": .string("function_call_output"), "call_id": .string("call"), "output": .string("7")])
        ])
    }

    @Test("Tool-name mapping keeps literal Unicode identities", arguments: [false, true])
    func literalToolNames(decomposed: Bool) async throws {
        let capture = Capture()
        let name = decomposed ? "e\u{0301}" : "é"
        _ = try await provider(capture).responses("gpt-6").doGenerate(options: .init(prompt: [], tools: [
            .provider(.init(id: "openai.web_search", name: "e\u{0301}", args: [:])),
            .provider(.init(id: "openai.code_interpreter", name: "é", args: [:]))
        ], toolChoice: .tool(toolName: name)))
        guard case .object(let body)? = await capture.value() else { Issue.record("Missing request"); return }
        #expect(body["tool_choice"] == .object(["type": .string(decomposed ? "web_search" : "code_interpreter")]))
    }

    @Test("Existing tool arguments project nested objects and retain supported image options")
    func toolArguments() async throws {
        let capture = Capture()
        let interpreter = openaiTools.codeInterpreter(.init(container: .auto(fileIds: ["file_data"])))
        let secret: [String: JSONValue] = ["domain": .string("a"), "name": .string("b"), "value": .string("c")]
        let policy: JSONValue = .object([
            "type": .string("allowlist"), "allowedDomains": .array([]),
            "domainSecrets": .array([.object(secret.merging(["extra": .bool(true)]) { _, new in new })])
        ])
        _ = try await provider(capture).responses("gpt-6").doGenerate(options: .init(prompt: [], tools: [
            .provider(.init(id: "openai.file_search", name: "docs", args: [
                "vectorStoreIds": .array([]), "ranking": .object([:]), "filters": .object([
                    "type": .string("eq"), "key": .string("tag"), "value": .string("x"), "extra": .bool(true)
                ])
            ])),
            .provider(.init(id: "openai.shell", name: "shell", args: ["environment": .object([
                "type": .string("containerAuto"), "networkPolicy": policy
            ])])),
            .provider(.init(id: "openai.web_search", name: "web", args: ["filters": .object(["blockedDomains": .array([.string("blocked.test")])])])),
            .provider(.init(id: "openai.image_generation", name: "image", args: ["action": .string("edit"), "quality": .string("max"), "moderation": .string("low"), "size": .string("1536x864")])),
            .provider(.init(id: try #require(interpreter.id), name: "python", args: interpreter.args ?? [:]))
        ]))
        guard case .object(let body)? = await capture.value(), case .array(let tools)? = body["tools"] else { Issue.record("Missing request"); return }
        #expect(tools.count == 5)
        #expect(tools.first == .object(["type": .string("file_search"), "vector_store_ids": .array([]), "ranking_options": .object([:]),
            "filters": .object(["type": .string("eq"), "key": .string("tag"), "value": .string("x")])]))
        #expect(tools[1] == .object(["type": .string("shell"), "environment": .object([
            "type": .string("container_auto"), "network_policy": .object([
                "type": .string("allowlist"), "allowed_domains": .array([]), "domain_secrets": .array([.object(secret)])
            ])
        ])]))
        #expect(tools[2] == .object(["type": .string("web_search"), "filters": .object(["blocked_domains": .array([.string("blocked.test")])])]))
        #expect(tools[3] == .object(["type": .string("image_generation"), "action": .string("edit"), "quality": .string("max"), "moderation": .string("low"), "size": .string("1536x864")]))
        #expect(tools[4] == .object(["type": .string("code_interpreter"), "container": .object(["type": .string("auto"), "file_ids": .array([.string("file_data")])])]))
    }

    @Test("Optional tool configuration rejects null and image generation rejects unknown keys", arguments: [
        ("openai.code_interpreter", "container", JSONValue.null), ("openai.tool_search", "execution", .null),
        ("openai.file_search", "maxNumResults", .null), ("openai.mcp", "authorization", .null),
        ("openai.shell", "environment", .null), ("openai.image_generation", "extra", .bool(true)),
        ("openai.image_generation", "size", .string("1x2\n"))
    ])
    func invalidToolArguments(id: String, key: String, value: JSONValue) async throws {
        let capture = Capture()
        var args: [String: JSONValue] = [key: value]
        if id == "openai.file_search" { args["vectorStoreIds"] = .array([]) }
        if id == "openai.mcp" { args["serverLabel"] = .string("docs"); args["serverUrl"] = .string("") }
        await #expect(throws: TypeValidationError.self) {
            try await provider(capture).responses("gpt-6").doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: id, name: "tool", args: args))]))
        }
    }

    @Test("File search requires representable integer limits", arguments: [2.5, 1e20])
    func fileSearchNumericLimit(limit: Double) async throws {
        let capture = Capture()
        await #expect(throws: TypeValidationError.self) {
            _ = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: "openai.file_search", name: "documents", args: [
                "vectorStoreIds": .array([.string("vs_documents")]), "maxNumResults": .number(limit)
            ]))]))
        }
    }

    @Test("Fast service tier uses priority capabilities", arguments: ["gpt-4.1", "gpt-5-nano"])
    func fastServiceTier(modelId: String) async throws {
        let capture = Capture()
        let result = try await provider(capture).responses(modelId: .init(rawValue: modelId)).doGenerate(options: .init(
            prompt: [], providerOptions: ["openai": ["serviceTier": .string("fast")]]
        ))
        let body = try #require(await capture.value())
        guard case .object(let object) = body else { Issue.record("Missing request object"); return }
        let supportsPriority = modelId == "gpt-4.1"
        #expect(object["service_tier"] == (supportsPriority ? .string("fast") : nil))
        #expect(result.warnings.contains { if case .unsupported(feature: "serviceTier", details: _) = $0 { return true }; return false } == !supportsPriority)
    }

    @Test("Ultrafast service tier passes through as an API option")
    func ultrafastServiceTier() async throws {
        let capture = Capture()
        _ = try await provider(capture).responses("gpt-5.6-sol").doGenerate(options: .init(
            prompt: [], providerOptions: ["openai": ["serviceTier": .string("ultrafast")]]
        ))
        let body = try #require(await capture.value())
        guard case .object(let object) = body else { Issue.record("Missing request object"); return }
        #expect(object["service_tier"] == .string("ultrafast"))
    }

    @Test("Media type separators retain scalar semantics before URL and inline conversion")
    func requestMediaTypeSeparators() async throws {
        let capture = Capture()
        let mediaType = "image/\u{0301}*"
        _ = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(prompt: [
            .user(content: [
                .file(.init(data: .url(URL(string: "https://example.com/image")!), mediaType: mediaType)),
                .file(.init(data: .data(Data([0x78])), mediaType: mediaType))
            ], providerOptions: nil)
        ]))
        guard case .object(let body)? = await capture.value(), case .array(let input)? = body["input"],
              case .object(let message)? = input.first else { Issue.record("Missing input"); return }
        #expect(message["content"] == .array([
            .object(["type": .string("input_image"), "image_url": .string("https://example.com/image")]),
            .object(["type": .string("input_image"), "image_url": .string("data:\(mediaType);base64,eA==")])
        ]))
    }

    @Test("Native media routing follows the declared HTTP URL capability", arguments: [
        ("https://example.com/a", true), ("HTTPS://example.com/a", false),
        ("https://example.com/a\n", false), ("https://example.com/\u{85}", true)
    ])
    func requestMediaRouting(url: String, supported: Bool) async throws {
        let model = try createOpenAI().responses("gpt-4.1")
        let urls = try await model.supportedUrls
        #expect(isUrlSupported(mediaType: "application/pdf", url: url, supportedUrls: urls) == supported)
    }

    @Test("Request schemas normalize unsupported response constraints")
    func responseSchemaNormalization() async throws {
        let capture = Capture()
        let result = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(
            prompt: [], responseFormat: .json(schema: .object([
                "type": .string("string"), "pattern": .string("(?=x)x")
            ]), name: nil, description: nil)
        ))
        guard case .object(let body)? = await capture.value(), case .object(let text)? = body["text"],
              case .object(let format)? = text["format"] else { Issue.record("Missing response format"); return }
        #expect(format["schema"] == .object(["type": .string("string")]))
        #expect(result.warnings.contains { if case .compatibility = $0 { return true }; return false })
    }

    @Test("Reasoning capabilities resolve portable effort before sampling and logprobs", arguments: ["gpt-6-astra", "gpt-6-sol", "gpt-5.6"])
    func requestReasoningCapabilities(modelId: String) async throws {
        let capture = Capture()
        let result = try await provider(capture).responses(modelId).doGenerate(options: .init(
            prompt: [], temperature: 0.5, topP: 0.8, reasoning: LanguageModelV4ReasoningEffort.none,
            providerOptions: ["openai": [
                "reasoningEffort": modelId == "gpt-5.6" ? .string("high") : .null,
                "reasoningSummary": .null, "logprobs": .bool(true)
            ]]
        ))
        guard case .object(let body)? = await capture.value() else { Issue.record("Missing request"); return }
        let expectedEffort: JSONValue? = modelId == "gpt-6-astra" ? nil : .string(modelId == "gpt-6-sol" ? "none" : "high")
        let reasoning: [String: JSONValue]
        if case .object(let value)? = body["reasoning"] { reasoning = value } else { reasoning = [:] }
        #expect(reasoning["effort"] == expectedEffort)
        #expect(reasoning["summary"] == nil)
        #expect(body["temperature"] == (modelId == "gpt-6-sol" ? .number(0.5) : nil))
        #expect(body["top_p"] == (modelId == "gpt-6-sol" ? .number(0.8) : nil))
        #expect(body["top_logprobs"] == (modelId == "gpt-6-astra" ? nil : .number(20)))
        #expect(body["include"] == (modelId == "gpt-6-astra" ? nil : .array([.string("message.output_text.logprobs")])))
        let features = Set(result.warnings.compactMap { warning -> String? in
            if case .unsupported(let feature, _) = warning { return feature }; return nil
        })
        #expect(features == (modelId == "gpt-6-astra" ? ["reasoningEffort", "temperature", "topP", "logprobs"] : modelId == "gpt-6-sol" ? [] : ["temperature", "topP"]))
    }

    @Test("Explicit include order and duplicates survive automatic additions", arguments: [false, true])
    func requestIncludes(webSources: Bool) async throws {
        let capture = Capture()
        let initial = ["file_search_call.results", "reasoning.encrypted_content", "file_search_call.results"]
        _ = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(
            prompt: [], tools: [
                .provider(.init(id: "openai.web_search", name: "browse", args: [:])),
                .provider(.init(id: "openai.code_interpreter", name: "python", args: [:]))
            ], providerOptions: ["openai": [
                "include": .array(initial.map(JSONValue.string)), "includeWebSearchSources": .bool(webSources)
            ]]
        ))
        guard case .object(let body)? = await capture.value() else { Issue.record("Missing request"); return }
        let expected = initial + (webSources ? ["web_search_call.action.sources"] : []) + ["code_interpreter_call.outputs"]
        #expect(body["include"] == .array(expected.map(JSONValue.string)))
    }

    @Test("Compaction appends its trigger after history and rejects obsolete cache retention")
    func requestCompactionAndCache() async throws {
        let capture = Capture()
        let result = try await provider(capture).responses("gpt-6-astra").doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Compact this history"))], providerOptions: nil)],
            providerOptions: OpenAIProvider.responsesOptions(.init(
                maxToolCalls: 3, promptCacheOptions: .init(ttl: .thirtyMinutes), promptCacheRetention: "24h",
                contextManagement: [.init(compactThreshold: 2)], compactionTrigger: true
            ))
        ))
        guard case .object(let body)? = await capture.value(), case .array(let input)? = body["input"] else {
            Issue.record("Missing input"); return
        }
        #expect(input.count == 2)
        #expect(input.last == .object(["type": .string("compaction_trigger")]))
        #expect(body["context_management"] == .array([.object(["type": .string("compaction"), "compact_threshold": .number(2)])]))
        #expect(body["prompt_cache_options"] == .object(["ttl": .string("30m")]))
        #expect(body["prompt_cache_retention"] == nil)
        #expect(body["max_tool_calls"] == .number(3))
        #expect(result.warnings.contains { if case .unsupported("promptCacheRetention", _) = $0 { return true }; return false })
    }

    @Test("Null request fields remain distinct from absent options")
    func requestNullFields() async throws {
        let capture = Capture()
        let fields = ["conversation", "include", "maxToolCalls", "metadata", "parallelToolCalls", "previousResponseId", "promptCacheKey", "promptCacheRetention", "store", "user", "instructions", "safetyIdentifier", "serviceTier", "truncation"]
        _ = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(
            prompt: [], providerOptions: ["openai": Dictionary(uniqueKeysWithValues: fields.map { ($0, JSONValue.null) })]
        ))
        guard case .object(let body)? = await capture.value() else { Issue.record("Missing request"); return }
        for key in ["conversation", "include", "max_tool_calls", "metadata", "parallel_tool_calls", "previous_response_id", "prompt_cache_key", "prompt_cache_retention", "store", "user", "instructions", "safety_identifier", "service_tier", "truncation"] {
            #expect(body[key] == .null)
        }
    }

    @Test("Raw prompt cache directives retain false and unprojected fields", arguments: [
        JSONValue.bool(false), .object(["mode": .string("future"), "extra": .array([.number(1)])])
    ])
    func requestRawCacheDirectives(directive: JSONValue) async throws {
        let capture = Capture()
        let options: SharedV4ProviderOptions = ["openai": ["promptCacheBreakpoint": directive]]
        _ = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(prompt: [
            .system(content: "System", providerOptions: options),
            .user(content: [.text(.init(text: "User", providerOptions: options))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "lookup", output: .text(value: "Result", providerOptions: options),
                providerOptions: ["openai": ["promptCacheBreakpoint": .object(["mode": .string("explicit")])]]))], providerOptions: nil)
        ]))
        guard case .object(let body)? = await capture.value(), case .array(let input)? = body["input"], input.count == 3 else {
            Issue.record("Missing input"); return
        }
        for (index, key) in [(0, "content"), (1, "content"), (2, "output")] {
            guard case .object(let item) = input[index], case .array(let parts)? = item[key],
                  case .object(let part)? = parts.first else { Issue.record("Missing cache directive content"); continue }
            #expect(part["prompt_cache_breakpoint"] == directive)
        }
    }

    @Test("Invalid request configuration is refused before HTTP", arguments: ["reasoningMode", "reasoningContext", "includeWebSearchSources", "compactionTrigger", "promptCacheOptions", "systemMessageMode", "logprobs", "include"])
    func requestOptionsRejectInvalid(key: String) async throws {
        let provider = try createOpenAI(settings: .init(apiKey: "test", fetch: { _ in throw URLError(.badServerResponse) }))
        await #expect(throws: InvalidArgumentError.self) {
            try await provider.responses("gpt-5.6-sol").doGenerate(options: .init(
                prompt: [], providerOptions: ["openai": [key: key == "include" ? .array([.string("web_search_call.action.sources")]) : .null]]
            ))
        }
    }
}
