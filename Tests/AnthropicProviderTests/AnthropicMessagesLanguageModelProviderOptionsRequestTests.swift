import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let providerOptionsTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func makeProviderOptionsTestConfig(
    provider: String = "anthropic.messages",
    fetch: @escaping FetchFunction
) -> AnthropicMessagesConfig {
    AnthropicMessagesConfig(
        provider: provider,
        baseURL: "https://api.anthropic.com/v1",
        headers: { [
            "x-api-key": "test-key",
            "anthropic-version": "2023-06-01"
        ] },
        fetch: fetch,
        supportedUrls: { [:] },
        generateId: { "generated-id" }
    )
}

private func makeProviderOptionsTestResponseData(model: String) throws -> Data {
    let json: [String: Any] = [
        "type": "message",
        "id": "msg_test",
        "model": model,
        "content": [],
        "stop_reason": "end_turn",
        "stop_sequence": NSNull(),
        "usage": [
            "input_tokens": 1,
            "output_tokens": 1,
        ],
    ]
    return try JSONSerialization.data(withJSONObject: json)
}

private func makeProviderOptionsTestHTTPResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

private actor RequestCapture {
    private var request: URLRequest?
    func store(_ request: URLRequest) { self.request = request }
    func current() -> URLRequest? { request }
}

private func decodeRequestJSON(_ request: URLRequest?) -> [String: Any]? {
    guard let request,
          let body = request.httpBody,
          let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else { return nil }
    return json
}

private func anthropicBetaSet(_ request: URLRequest?) -> Set<String>? {
    guard let request else { return nil }
    let headers = request.allHTTPHeaderFields ?? [:]
    guard let value = headers["anthropic-beta"] else { return nil }
    let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return Set(parts)
}

@Suite("AnthropicMessagesLanguageModel provider options -> request")
struct AnthropicMessagesLanguageModelProviderOptionsRequestTests {
    @Test("sends mcpServers payload and beta")
    func sendsMcpServers() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "mcpServers": .array([
                        .object([
                            "type": .string("url"),
                            "name": .string("echo"),
                            "url": .string("https://example.com/mcp"),
                            "authorizationToken": .string("secret-token"),
                            "toolConfiguration": .object([
                                "allowedTools": .array([.string("echo")]),
                                "enabled": .bool(true),
                            ]),
                        ])
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let servers = json?["mcp_servers"] as? [[String: Any]],
           let first = servers.first,
           let toolConfig = first["tool_configuration"] as? [String: Any] {
            #expect(first["type"] as? String == "url")
            #expect(first["name"] as? String == "echo")
            #expect(first["url"] as? String == "https://example.com/mcp")
            #expect(first["authorization_token"] as? String == "secret-token")
            #expect(toolConfig["enabled"] as? Bool == true)
            #expect(toolConfig["allowed_tools"] as? [String] == ["echo"])
        } else {
            Issue.record("Expected mcp_servers payload")
        }

        #expect(anthropicBetaSet(await capture.current()) == Set(["mcp-client-2025-04-04"]))
    }

    @Test("sends effort output_config and beta")
    func sendsEffort() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "effort": .string("medium")
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let outputConfig = json?["output_config"] as? [String: Any] {
            #expect(outputConfig["effort"] as? String == "medium")
        } else {
            Issue.record("Expected output_config payload")
        }

        #expect(anthropicBetaSet(await capture.current()) == nil)
    }

    @Test("reads provider options from custom provider key")
    func readsProviderOptionsFromCustomKey() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(
                provider: "custom-anthropic",
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "custom-anthropic": [
                    "effort": .string("medium")
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let outputConfig = json?["output_config"] as? [String: Any] {
            #expect(outputConfig["effort"] as? String == "medium")
        } else {
            Issue.record("Expected output_config payload")
        }

        #expect(anthropicBetaSet(await capture.current()) == nil)
    }

    @Test("custom provider key: passes disableParallelToolUse via tool_choice")
    func customProviderKeyPassesDisableParallelToolUse() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let toolSchema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            tools: [.function(.init(name: "testTool", inputSchema: toolSchema))],
            providerOptions: [
                "custom-anthropic": [
                    "disableParallelToolUse": .bool(true)
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let toolChoice = json?["tool_choice"] as? [String: Any] {
            #expect(toolChoice["type"] as? String == "auto")
            #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)
        } else {
            Issue.record("Expected tool_choice payload")
        }
    }

    @Test("canonical provider key: passes disableParallelToolUse for custom provider name")
    func canonicalProviderKeyPassesDisableParallelToolUseForCustomProviderName() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let toolSchema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            tools: [.function(.init(name: "testTool", inputSchema: toolSchema))],
            providerOptions: [
                "anthropic": [
                    "disableParallelToolUse": .bool(true)
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let toolChoice = json?["tool_choice"] as? [String: Any] {
            #expect(toolChoice["type"] as? String == "auto")
            #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)
        } else {
            Issue.record("Expected tool_choice payload")
        }
    }

    @Test("uses native output_format for structured outputs when supported")
    func usesNativeStructuredOutputs() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-sonnet-4-5-20250929")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-5-20250929"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": .string("string")])
            ]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            responseFormat: .json(schema: schema, name: nil, description: nil)
        ))

        let json = decodeRequestJSON(await capture.current())
        if let outputFormat = json?["output_format"] as? [String: Any] {
            #expect(outputFormat["type"] as? String == "json_schema")
            #expect(outputFormat["schema"] != nil)
        } else {
            Issue.record("Expected output_format payload")
        }

        #expect(json?["tool_choice"] == nil)
        #expect(json?["tools"] == nil)
        #expect(anthropicBetaSet(await capture.current()) == Set(["structured-outputs-2025-11-13"]))
    }

    @Test("sends context_management edits mapping and beta")
    func sendsContextManagement() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "contextManagement": .object([
                        "edits": .array([
                            .object([
                                "type": .string("clear_tool_uses_20250919"),
                                "trigger": .object([
                                    "type": .string("tool_uses"),
                                    "value": .number(5),
                                ]),
                                "keep": .object([
                                    "type": .string("tool_uses"),
                                    "value": .number(2),
                                ]),
                                "clearAtLeast": .object([
                                    "type": .string("input_tokens"),
                                    "value": .number(1000),
                                ]),
                                "clearToolInputs": .bool(true),
                                "excludeTools": .array([.string("search")]),
                            ]),
                            .object([
                                "type": .string("clear_thinking_20251015"),
                                "keep": .string("all"),
                            ]),
                        ])
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let contextManagement = json?["context_management"] as? [String: Any],
           let edits = contextManagement["edits"] as? [[String: Any]],
           let first = edits.first {
            #expect(first["type"] as? String == "clear_tool_uses_20250919")
            #expect(first["clear_tool_inputs"] as? Bool == true)
            #expect(first["exclude_tools"] as? [String] == ["search"])

            if let trigger = first["trigger"] as? [String: Any] {
                #expect(trigger["type"] as? String == "tool_uses")
                #expect(trigger["value"] as? Double == 5)
            } else {
                Issue.record("Expected trigger mapping")
            }

            if let clearAtLeast = first["clear_at_least"] as? [String: Any] {
                #expect(clearAtLeast["type"] as? String == "input_tokens")
                #expect(clearAtLeast["value"] as? Double == 1000)
            } else {
                Issue.record("Expected clear_at_least mapping")
            }
        } else {
            Issue.record("Expected context_management payload")
        }

        #expect(anthropicBetaSet(await capture.current()) == Set(["context-management-2025-06-27"]))
    }

    @Test("sends adaptive thinking payload and suppresses sampling params")
    func sendsAdaptiveThinking() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-sonnet-4-5-20250929")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-5-20250929"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            temperature: 0.5,
            topP: 0.9,
            topK: 10,
            providerOptions: [
                "anthropic": [
                    "thinking": .object([
                        "type": .string("adaptive")
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let thinking = json?["thinking"] as? [String: Any] {
            #expect(thinking["type"] as? String == "adaptive")
            // Adaptive mode does not use budget_tokens
            #expect(thinking["budget_tokens"] == nil)
        } else {
            Issue.record("Expected thinking payload")
        }

        // Sampling params are suppressed in adaptive mode, same as manual thinking
        #expect(json?["temperature"] == nil)
        #expect(json?["top_k"] == nil)
        #expect(json?["top_p"] == nil)
    }

    @Test("sends thinking.display when set on adaptive thinking")
    func sendsAdaptiveThinkingWithDisplay() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-opus-4-7")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-opus-4-7"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "thinking": .object([
                        "type": .string("adaptive"),
                        "display": .string("summarized"),
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let thinking = json?["thinking"] as? [String: Any] {
            #expect(thinking["type"] as? String == "adaptive")
            #expect(thinking["display"] as? String == "summarized")
        } else {
            Issue.record("Expected thinking payload")
        }
    }

    @Test("sends thinking.display when set on enabled thinking")
    func sendsEnabledThinkingWithDisplay() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-sonnet-4-5-20250929")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-5-20250929"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "thinking": .object([
                        "type": .string("enabled"),
                        "budgetTokens": .number(2048),
                        "display": .string("omitted"),
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let thinking = json?["thinking"] as? [String: Any] {
            #expect(thinking["type"] as? String == "enabled")
            #expect(thinking["budget_tokens"] as? Double == 2048)
            #expect(thinking["display"] as? String == "omitted")
        } else {
            Issue.record("Expected thinking payload")
        }
    }

    @Test("omits thinking.display when not set")
    func omitsDisplayWhenNotSet() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-sonnet-4-5-20250929")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-5-20250929"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "thinking": .object([
                        "type": .string("adaptive")
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let thinking = json?["thinking"] as? [String: Any] {
            #expect(thinking["type"] as? String == "adaptive")
            #expect(thinking["display"] == nil)
        } else {
            Issue.record("Expected thinking payload")
        }
    }

    @Test("sends speed=fast and fast-mode beta header")
    func sendsSpeedFast() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-opus-4-6")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-opus-4-6"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "speed": .string("fast")
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        #expect(json?["speed"] as? String == "fast")
        #expect(anthropicBetaSet(await capture.current()) == Set(["fast-mode-2026-02-01"]))
    }

    @Test("sends speed=standard without fast-mode beta header")
    func sendsSpeedStandard() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-opus-4-6")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-opus-4-6"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "speed": .string("standard")
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        #expect(json?["speed"] as? String == "standard")
        // standard speed does not add a beta header
        #expect(anthropicBetaSet(await capture.current()) == nil)
    }

    @Test("sends effort=max output_config and beta")
    func sendsEffortMax() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-opus-4-6")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-opus-4-6"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "effort": .string("max")
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let outputConfig = json?["output_config"] as? [String: Any] {
            #expect(outputConfig["effort"] as? String == "max")
        } else {
            Issue.record("Expected output_config payload")
        }

        #expect(anthropicBetaSet(await capture.current()) == nil)
    }

    @Test("sends compact_20260112 with trigger")
    func sendsCompactWithTrigger() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "contextManagement": .object([
                        "edits": .array([
                            .object([
                                "type": .string("compact_20260112"),
                                "trigger": .object([
                                    "type": .string("input_tokens"),
                                    "value": .number(50000),
                                ]),
                            ])
                        ])
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let contextManagement = json?["context_management"] as? [String: Any],
           let edits = contextManagement["edits"] as? [[String: Any]],
           let first = edits.first {
            #expect(first["type"] as? String == "compact_20260112")
            if let trigger = first["trigger"] as? [String: Any] {
                #expect(trigger["type"] as? String == "input_tokens")
                #expect(trigger["value"] as? Double == 50000)
            } else {
                Issue.record("Expected trigger in compact edit")
            }
        } else {
            Issue.record("Expected context_management payload")
        }
    }

    @Test("sends compact_20260112 with all options")
    func sendsCompactWithAllOptions() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "contextManagement": .object([
                        "edits": .array([
                            .object([
                                "type": .string("compact_20260112"),
                                "trigger": .object([
                                    "type": .string("input_tokens"),
                                    "value": .number(50000),
                                ]),
                                "pauseAfterCompaction": .bool(true),
                                "instructions": .string("Summarize the conversation concisely."),
                            ])
                        ])
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let contextManagement = json?["context_management"] as? [String: Any],
           let edits = contextManagement["edits"] as? [[String: Any]],
           let first = edits.first {
            #expect(first["type"] as? String == "compact_20260112")
            // camelCase → snake_case mapping
            #expect(first["pause_after_compaction"] as? Bool == true)
            #expect(first["instructions"] as? String == "Summarize the conversation concisely.")
        } else {
            Issue.record("Expected context_management payload with compact options")
        }
    }

    @Test("sends compact_20260112 and adds both compact and context-management betas")
    func sendsCompactBetas() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "contextManagement": .object([
                        "edits": .array([
                            .object(["type": .string("compact_20260112")])
                        ])
                    ])
                ]
            ]
        ))

        let betas = anthropicBetaSet(await capture.current())
        #expect(betas?.contains("compact-2026-01-12") == true)
        #expect(betas?.contains("context-management-2025-06-27") == true)
    }

    @Test("sends container id as string without skills")
    func sendsContainerIdOnly() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "container": .object([
                        "id": .string("container_123")
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        #expect(json?["container"] as? String == "container_123")
        #expect(anthropicBetaSet(await capture.current()) == nil)
    }

    @Test("sends container object with skills and adds betas")
    func sendsContainerWithSkills() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "container": .object([
                        "id": .string("container_123"),
                        "skills": .array([
                            .object([
                                "type": .string("anthropic"),
                                "skillId": .string("tool_search"),
                                "version": .string("1.0.0"),
                            ])
                        ])
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let container = json?["container"] as? [String: Any],
           let skills = container["skills"] as? [[String: Any]],
           let first = skills.first {
            #expect(container["id"] as? String == "container_123")
            #expect(first["type"] as? String == "anthropic")
            #expect(first["skill_id"] as? String == "tool_search")
            #expect(first["version"] as? String == "1.0.0")
        } else {
            Issue.record("Expected container object payload with skills")
        }

        #expect(
            anthropicBetaSet(await capture.current())
                == Set([
                    "code-execution-2025-08-25",
                    "files-api-2025-04-14",
                    "skills-2025-10-02",
                ])
        )
    }

    @Test("sends top-level cache_control for automatic caching")
    func sendsCacheControl() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "cacheControl": .object(["type": .string("ephemeral")])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let cacheControl = json?["cache_control"] as? [String: Any] {
            #expect(cacheControl["type"] as? String == "ephemeral")
        } else {
            Issue.record("Expected top-level cache_control payload")
        }
    }

    @Test("sends top-level cache_control with ttl")
    func sendsCacheControlWithTTL() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "cacheControl": .object([
                        "type": .string("ephemeral"),
                        "ttl": .string("1h"),
                    ])
                ]
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        if let cacheControl = json?["cache_control"] as? [String: Any] {
            #expect(cacheControl["type"] as? String == "ephemeral")
            #expect(cacheControl["ttl"] as? String == "1h")
        } else {
            Issue.record("Expected top-level cache_control payload with ttl")
        }
    }

    @Test("sends top-level cache_control via doStream providerOptions")
    func sendsCacheControlViaDoStream() async throws {
        let capture = RequestCapture()

        // Minimal SSE streaming response
        let ssePayloads = [
            #"{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":1},"content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}}"#,
            #"{"type":"message_stop"}"#,
        ]

        let sseBody = ssePayloads.map { "event: message\ndata: \($0)\n\n" }.joined()
        let sseData = Data(sseBody.utf8)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(
                body: .data(sseData),
                urlResponse: makeProviderOptionsTestHTTPResponse()
            )
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "cacheControl": .object(["type": .string("ephemeral")])
                ]
            ]
        ))

        // Consume the stream to trigger the request
        for try await _ in result.stream {}

        let json = decodeRequestJSON(await capture.current())
        if let cacheControl = json?["cache_control"] as? [String: Any] {
            #expect(cacheControl["type"] as? String == "ephemeral")
        } else {
            Issue.record("Expected top-level cache_control in doStream request body. Keys: \(json?.keys.sorted() ?? [])")
        }
    }

    @Test("sends cache_control when providerOptions are built via JSON round-trip")
    func sendsCacheControlViaJSONRoundTrip() async throws {
        // Simulate the exact pattern Symphony uses:
        // 1. Build options with sendReasoning (like buildProviderOptions)
        // 2. Encode as JSON, decode as ProviderOptions
        // 3. Re-encode, add cacheControl, decode again
        // 4. Pass to doGenerate and verify cache_control in body

        // Step 1: Build initial options (simulating buildProviderOptions)
        let initialJSON: [String: [String: JSONValue]] = [
            "anthropic": ["sendReasoning": .bool(true)]
        ]
        let initialData = try JSONEncoder().encode(initialJSON)
        let existing = try JSONDecoder().decode(ProviderOptions.self, from: initialData)

        // Step 2: Round-trip and merge cacheControl (simulating mergeAutomaticCaching)
        // CRITICAL: Symphony decodes as its own JSONValue type, not the SDK's.
        // But since we can't import SymphonyShared here, we simulate by
        // decoding as a generic JSON structure via JSONSerialization
        let existingData = try JSONEncoder().encode(existing)

        // Parse as Foundation types (simulating cross-module decode)
        guard let foundation = try JSONSerialization.jsonObject(with: existingData) as? [String: [String: Any]] else {
            Issue.record("Failed to parse existing options as Foundation dict")
            return
        }

        // Add cacheControl using Foundation types
        var mutable = foundation
        var anthropic = mutable["anthropic"] ?? [:]
        anthropic["cacheControl"] = ["type": "ephemeral"]
        mutable["anthropic"] = anthropic

        // Re-encode back to JSON and decode as ProviderOptions
        let mergedFoundationData = try JSONSerialization.data(withJSONObject: mutable)
        let merged = try JSONDecoder().decode(ProviderOptions.self, from: mergedFoundationData)

        // Verify the merged options have both keys
        let anthropicOpts = try #require(merged["anthropic"])
        #expect(anthropicOpts["sendReasoning"] == .bool(true))
        #expect(anthropicOpts["cacheControl"] != nil)

        // Step 3: Pass to doGenerate and verify serialized body
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: merged
        ))

        let json = decodeRequestJSON(await capture.current())
        if let cacheControl = json?["cache_control"] as? [String: Any] {
            #expect(cacheControl["type"] as? String == "ephemeral")
        } else {
            let bodyData = await capture.current()?.httpBody
            let bodyStr = bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
            Issue.record("Expected top-level cache_control after cross-type round-trip. Body: \(bodyStr.prefix(500))")
        }
    }

    // MARK: - User-supplied anthropic-beta merging
    //
    // Mirrors `getBetasFromHeaders` and the typed `anthropicBeta` provider
    // option from the upstream TypeScript SDK. User-supplied beta values
    // (via `AnthropicProviderSettings.headers`, `CallSettings.headers`,
    // or `AnthropicProviderOptions.anthropicBeta`) must be merged with
    // the SDK's auto-collected betas into a single deduplicated
    // `anthropic-beta` header, instead of overwriting them.

    @Test("merges user-supplied anthropic-beta from CallSettings.headers with SDK betas")
    func mergesCallSettingsBetaWithSDKBetas() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        // mcp-client-2025-04-04 is added by the SDK (mcpServers); the
        // user's extended-cache-ttl beta must be unioned with it.
        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            headers: ["anthropic-beta": "extended-cache-ttl-2025-04-11"],
            providerOptions: [
                "anthropic": [
                    "mcpServers": .array([
                        .object([
                            "type": .string("url"),
                            "name": .string("echo"),
                            "url": .string("https://example.com/mcp"),
                        ])
                    ])
                ]
            ]
        ))

        let betas = anthropicBetaSet(await capture.current())
        #expect(betas == Set(["extended-cache-ttl-2025-04-11", "mcp-client-2025-04-04"]))
    }

    @Test("merges user-supplied anthropic-beta from provider settings.headers with SDK betas")
    func mergesProviderSettingsBetaWithSDKBetas() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        // Add anthropic-beta to the provider's static headers (settings.headers).
        let configHeaders = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-key",
                "anthropic-version": "2023-06-01",
                "anthropic-beta": "extended-cache-ttl-2025-04-11",
            ] },
            fetch: fetch,
            supportedUrls: { [:] },
            generateId: { "generated-id" }
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: configHeaders
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "mcpServers": .array([
                        .object([
                            "type": .string("url"),
                            "name": .string("settings-merge"),
                            "url": .string("https://example.com/mcp"),
                        ])
                    ])
                ]
            ]
        ))

        let betas = anthropicBetaSet(await capture.current())
        #expect(betas == Set(["extended-cache-ttl-2025-04-11", "mcp-client-2025-04-04"]))
    }

    @Test("merges anthropic-beta from both provider settings and CallSettings without legacy fine-grained-tool-streaming")
    func mergesProviderSettingsAndCallSettingsBetas() async throws {
        // Mirrors the upstream test
        // `should merge custom anthropic-beta headers without legacy fine-grained-tool-streaming beta`.
        // No tools and no provider options that add betas — only the
        // user-supplied ones from settings.headers and CallSettings.headers
        // should appear.
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let configHeaders = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-key",
                "anthropic-version": "2023-06-01",
                "anthropic-beta": "CONFIG-beta1,config-beta2",
            ] },
            fetch: fetch,
            supportedUrls: { [:] },
            generateId: { "generated-id" }
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: configHeaders
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            headers: ["anthropic-beta": "REQUEST-beta1,request-beta2"]
        ))

        // All four entries are present and lowercased; no other betas
        // are added because this request has no tools and no other
        // provider options.
        let betas = anthropicBetaSet(await capture.current())
        #expect(betas == Set(["config-beta1", "config-beta2", "request-beta1", "request-beta2"]))
    }

    @Test("includes providerOptions.anthropic.anthropicBeta in anthropic-beta header")
    func includesAnthropicBetaProviderOption() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "anthropicBeta": .array([
                        .string("my-beta-2025-01-01"),
                        .string("another-beta-2025-06-01"),
                    ])
                ]
            ]
        ))

        let betas = anthropicBetaSet(await capture.current())
        #expect(betas?.contains("my-beta-2025-01-01") == true)
        #expect(betas?.contains("another-beta-2025-06-01") == true)
    }

    @Test("trims and lowercases anthropicBeta provider option entries")
    func sanitizesAnthropicBetaProviderOptionEntries() async throws {
        // Defensive: the typed `anthropicBeta` array on
        // `AnthropicProviderOptions` flows directly into the
        // `anthropic-beta` header. Values must be trimmed (CRLF defense)
        // and lowercased (Anthropic treats beta names case-insensitively
        // and the SDK normalizes header-string sources the same way).
        // Empty entries — including those that become empty after
        // trimming — must be dropped so they don't introduce stray
        // commas in the final header value.
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            providerOptions: [
                "anthropic": [
                    "anthropicBeta": .array([
                        .string("  Mixed-Case-Beta-2025-01-01  "),
                        .string(""),
                        .string("   "),
                    ])
                ]
            ]
        ))

        let betas = anthropicBetaSet(await capture.current())
        #expect(betas == Set(["mixed-case-beta-2025-01-01"]))
    }

    @Test("deduplicates anthropic-beta entries across all sources")
    func deduplicatesBetaEntries() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let configHeaders = AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: { [
                "x-api-key": "test-key",
                "anthropic-version": "2023-06-01",
                "anthropic-beta": "extended-cache-ttl-2025-04-11",
            ] },
            fetch: fetch,
            supportedUrls: { [:] },
            generateId: { "generated-id" }
        )

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: configHeaders
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            headers: ["anthropic-beta": "extended-cache-ttl-2025-04-11"],
            providerOptions: [
                "anthropic": [
                    "anthropicBeta": .array([.string("extended-cache-ttl-2025-04-11")])
                ]
            ]
        ))

        let betas = anthropicBetaSet(await capture.current())
        #expect(betas == Set(["extended-cache-ttl-2025-04-11"]))
    }

    // MARK: - eager_input_streaming (GA replacement for fine-grained-tool-streaming beta)

    @Test("defaults to per-tool eager_input_streaming on streaming requests")
    func defaultsEagerInputStreamingOnStream() async throws {
        let capture = RequestCapture()

        let ssePayloads = [
            #"{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1},"content":[]}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}}"#,
            #"{"type":"message_stop"}"#,
        ]
        let sseBody = ssePayloads.map { "event: message\ndata: \($0)\n\n" }.joined()
        let sseData = Data(sseBody.utf8)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(sseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: providerOptionsTestPrompt,
            tools: [
                .function(.init(
                    name: "get_weather",
                    inputSchema: .object([:]),
                    description: "Get weather"
                ))
            ]
        ))
        for try await _ in result.stream {}

        let json = decodeRequestJSON(await capture.current())
        let tools = json?["tools"] as? [[String: Any]]
        #expect(tools?.first?["eager_input_streaming"] as? Bool == true)
        // No legacy beta header
        #expect(anthropicBetaSet(await capture.current()) == nil)
    }

    @Test("does not add eager_input_streaming when toolStreaming is false")
    func noEagerInputStreamingWhenOptOut() async throws {
        let capture = RequestCapture()

        let ssePayloads = [
            #"{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1},"content":[]}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}}"#,
            #"{"type":"message_stop"}"#,
        ]
        let sseBody = ssePayloads.map { "event: message\ndata: \($0)\n\n" }.joined()
        let sseData = Data(sseBody.utf8)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(sseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: providerOptionsTestPrompt,
            tools: [
                .function(.init(
                    name: "get_weather",
                    inputSchema: .object([:]),
                    description: "Get weather"
                ))
            ],
            providerOptions: ["anthropic": ["toolStreaming": .bool(false)]]
        ))
        for try await _ in result.stream {}

        let json = decodeRequestJSON(await capture.current())
        let tools = json?["tools"] as? [[String: Any]]
        #expect(tools?.first?["eager_input_streaming"] == nil)
    }

    @Test("does not default eager_input_streaming on non-streaming (generate) calls")
    func noEagerInputStreamingOnGenerate() async throws {
        let capture = RequestCapture()
        let responseData = try makeProviderOptionsTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeProviderOptionsTestHTTPResponse())
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeProviderOptionsTestConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: providerOptionsTestPrompt,
            tools: [
                .function(.init(
                    name: "get_weather",
                    inputSchema: .object([:]),
                    description: "Get weather"
                ))
            ]
        ))

        let json = decodeRequestJSON(await capture.current())
        let tools = json?["tools"] as? [[String: Any]]
        #expect(tools?.first?["eager_input_streaming"] == nil)
    }
}
