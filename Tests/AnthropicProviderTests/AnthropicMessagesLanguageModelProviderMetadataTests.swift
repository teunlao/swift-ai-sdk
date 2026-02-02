import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let metadataTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func makeMetadataTestConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
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
}

