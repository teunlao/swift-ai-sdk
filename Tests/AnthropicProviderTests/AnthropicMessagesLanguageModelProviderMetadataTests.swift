import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let metadataTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func makeMetadataTestConfig(
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

private func makeMinimalMetadataTestResponseData(model: String) throws -> Data {
    let json: [String: Any] = [
        "type": "message",
        "id": "msg_meta_min",
        "model": model,
        "content": [],
        "stop_reason": "end_turn",
        "stop_sequence": NSNull(),
        "usage": [
            "input_tokens": 1,
            "output_tokens": 2,
        ],
    ]
    return try JSONSerialization.data(withJSONObject: json)
}

private func makeMetadataTestHTTPResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func makeStream(from events: [String]) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(Data(event.utf8))
        }
        continuation.finish()
    }
}

private func events(from payloads: [String]) -> [String] {
    payloads.map { "data: \($0)\n\n" }
}

private func collectParts(from stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
    var parts: [LanguageModelV3StreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

@Suite("AnthropicMessagesLanguageModel provider metadata")
struct AnthropicMessagesLanguageModelProviderMetadataTests {
    @Test("maps container and contextManagement into provider metadata")
    func mapsContainerAndContextManagement() async throws {
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_meta",
            "model": "claude-sonnet-4-5-20250929",
            "content": [],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 1,
                "output_tokens": 2,
            ],
            "container": [
                "expires_at": "2026-01-01T00:00:00Z",
                "id": "container_123",
                "skills": [
                    [
                        "type": "anthropic",
                        "skill_id": "tool_search",
                        "version": "1.0.0",
                    ]
                ],
            ],
            "context_management": [
                "applied_edits": [
                    [
                        "type": "clear_tool_uses_20250919",
                        "cleared_tool_uses": 3,
                        "cleared_input_tokens": 100,
                    ]
                ]
            ],
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-5-20250929"),
            config: makeMetadataTestConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: metadataTestPrompt))

        let expectedContainer: JSONValue = .object([
            "expiresAt": .string("2026-01-01T00:00:00Z"),
            "id": .string("container_123"),
            "skills": .array([
                .object([
                    "type": .string("anthropic"),
                    "skillId": .string("tool_search"),
                    "version": .string("1.0.0"),
                ])
            ]),
        ])

        let expectedContextManagement: JSONValue = .object([
            "appliedEdits": .array([
                .object([
                    "type": .string("clear_tool_uses_20250919"),
                    "clearedToolUses": .number(3),
                    "clearedInputTokens": .number(100),
                ])
            ])
        ])

        #expect(result.providerMetadata?["anthropic"]?["container"] == expectedContainer)
        #expect(result.providerMetadata?["anthropic"]?["contextManagement"] == expectedContextManagement)
    }

    @Test("duplicates metadata under custom provider key when used")
    func duplicatesMetadataUnderCustomProviderKey() async throws {
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_meta_custom",
            "model": "claude-sonnet-4-5-20250929",
            "content": [],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 1,
                "output_tokens": 2,
            ],
            "container": [
                "expires_at": "2026-01-01T00:00:00Z",
                "id": "container_123",
                "skills": [
                    [
                        "type": "anthropic",
                        "skill_id": "tool_search",
                        "version": "1.0.0",
                    ]
                ],
            ],
            "context_management": [
                "applied_edits": [
                    [
                        "type": "clear_tool_uses_20250919",
                        "cleared_tool_uses": 3,
                        "cleared_input_tokens": 100,
                    ]
                ]
            ],
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = makeMetadataTestHTTPResponse()

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-5-20250929"),
            config: makeMetadataTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: metadataTestPrompt,
            providerOptions: [
                "custom-anthropic": [:]
            ]
        ))

        #expect(result.providerMetadata?["anthropic"] != nil)
        #expect(result.providerMetadata?["custom-anthropic"] != nil)
        #expect(result.providerMetadata?["custom-anthropic"]?["container"] == result.providerMetadata?["anthropic"]?["container"])
        #expect(result.providerMetadata?["custom-anthropic"]?["contextManagement"] == result.providerMetadata?["anthropic"]?["contextManagement"])
    }

    @Test("does not duplicate metadata when providerOptions uses canonical key")
    func doesNotDuplicateMetadataForCanonicalKey() async throws {
        let responseData = try makeMinimalMetadataTestResponseData(model: "claude-3-haiku-20240307")
        let httpResponse = makeMetadataTestHTTPResponse()

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeMetadataTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: metadataTestPrompt,
            providerOptions: [
                "anthropic": [:]
            ]
        ))

        #expect(result.providerMetadata?["anthropic"] != nil)
        #expect(result.providerMetadata?["custom-anthropic"] == nil)
        #expect(result.providerMetadata?.keys.sorted() == ["anthropic"])
    }

    @Test("does not duplicate metadata when no providerOptions used")
    func doesNotDuplicateMetadataWithoutProviderOptions() async throws {
        let responseData = try makeMinimalMetadataTestResponseData(model: "claude-3-haiku-20240307")
        let httpResponse = makeMetadataTestHTTPResponse()

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeMetadataTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(prompt: metadataTestPrompt))

        #expect(result.providerMetadata?["anthropic"] != nil)
        #expect(result.providerMetadata?["custom-anthropic"] == nil)
        #expect(result.providerMetadata?.keys.sorted() == ["anthropic"])
    }

    @Test("stream finish: does not duplicate metadata for canonical key")
    func streamFinishDoesNotDuplicateMetadataForCanonicalKey() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_custom_stream","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":20}}"#,
            #"{"type":"message_stop"}"#
        ]
        let streamEvents = events(from: payloads)
        let httpResponse = makeMetadataTestHTTPResponse()

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: streamEvents)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeMetadataTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: metadataTestPrompt,
            providerOptions: [
                "anthropic": [:]
            ]
        ))

        let parts = try await collectParts(from: result.stream)
        guard let finishPart = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
              case .finish(_, _, let metadata) = finishPart
        else {
            Issue.record("Missing finish part")
            return
        }

        #expect(metadata?["anthropic"] != nil)
        #expect(metadata?["custom-anthropic"] == nil)
        #expect(metadata?.keys.sorted() == ["anthropic"])
    }

    @Test("stream finish: duplicates metadata for custom provider key when used")
    func streamFinishDuplicatesMetadataUnderCustomProviderKey() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_custom_stream","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":20}}"#,
            #"{"type":"message_stop"}"#
        ]
        let streamEvents = events(from: payloads)
        let httpResponse = makeMetadataTestHTTPResponse()

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: streamEvents)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeMetadataTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: metadataTestPrompt,
            providerOptions: [
                "custom-anthropic": [:]
            ]
        ))

        let parts = try await collectParts(from: result.stream)
        guard let finishPart = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
              case .finish(_, _, let metadata) = finishPart
        else {
            Issue.record("Missing finish part")
            return
        }

        #expect(metadata?["anthropic"] != nil)
        #expect(metadata?["custom-anthropic"] != nil)
    }

    @Test("stream finish: does not duplicate metadata when no providerOptions used")
    func streamFinishDoesNotDuplicateMetadataWithoutProviderOptions() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_custom_stream","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":20}}"#,
            #"{"type":"message_stop"}"#
        ]
        let streamEvents = events(from: payloads)
        let httpResponse = makeMetadataTestHTTPResponse()

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(makeStream(from: streamEvents)), urlResponse: httpResponse)
        }

        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeMetadataTestConfig(provider: "custom-anthropic", fetch: fetch)
        )

        let result = try await model.doStream(options: .init(prompt: metadataTestPrompt))

        let parts = try await collectParts(from: result.stream)
        guard let finishPart = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
              case .finish(_, _, let metadata) = finishPart
        else {
            Issue.record("Missing finish part")
            return
        }

        #expect(metadata?["anthropic"] != nil)
        #expect(metadata?["custom-anthropic"] == nil)
        #expect(metadata?.keys.sorted() == ["anthropic"])
    }
}
