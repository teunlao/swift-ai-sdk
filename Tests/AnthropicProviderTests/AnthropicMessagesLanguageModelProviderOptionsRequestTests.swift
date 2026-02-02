import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let providerOptionsTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func makeProviderOptionsTestConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
    AnthropicMessagesConfig(
        provider: "anthropic.messages",
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

        #expect(anthropicBetaSet(await capture.current()) == Set(["effort-2025-11-24"]))
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
}

