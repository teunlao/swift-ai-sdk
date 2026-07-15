import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import AnthropicProvider

private let anthropicV4TestPrompt: LanguageModelV4Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private actor AnthropicV4RequestCapture {
    private var request: URLRequest?

    func store(_ request: URLRequest) {
        self.request = request
    }

    func current() -> URLRequest? {
        request
    }
}

private func makeAnthropicV4Response(model: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "type": "message",
        "id": "msg_v4_test",
        "model": model,
        "content": [],
        "stop_reason": "end_turn",
        "stop_sequence": NSNull(),
        "usage": [
            "input_tokens": 1,
            "output_tokens": 1,
        ],
    ])
}

private func makeAnthropicV4HTTPResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func makeAnthropicV4Model(
    modelId: String,
    capture: AnthropicV4RequestCapture
) throws -> AnthropicMessagesLanguageModelV4 {
    let responseData = try makeAnthropicV4Response(model: modelId)
    let fetch: FetchFunction = { request in
        await capture.store(request)
        return FetchResponse(
            body: .data(responseData),
            urlResponse: makeAnthropicV4HTTPResponse()
        )
    }
    return createAnthropic(settings: .init(apiKey: "test-key", fetch: fetch))
        .messages(modelId)
}

private func decodeAnthropicV4Request(_ request: URLRequest?) -> [String: Any]? {
    guard let body = request?.httpBody else { return nil }
    return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
}

private func anthropicV4BetaSet(_ request: URLRequest?) -> Set<String> {
    let value = request?.allHTTPHeaderFields?["anthropic-beta"] ?? ""
    return Set(value.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
}

@Suite("Anthropic Provider V4")
struct AnthropicProviderV4Tests {
    @Test("default and custom provider factories expose native V4 models")
    func exposesNativeV4Models() throws {
        let customProvider = createAnthropic(settings: .init(apiKey: "test-key"))
        let customModel = try customProvider.languageModel(modelId: "claude-sonnet-5")
        let defaultModel = try anthropic.languageModel(modelId: "claude-fable-5")
        let knownModelIds = Set(anthropicMessagesModelIds.map(\.rawValue))

        #expect(customProvider.specificationVersion == "v4")
        #expect(customModel.specificationVersion == "v4")
        #expect(defaultModel.specificationVersion == "v4")
        #expect(customModel is AnthropicMessagesLanguageModelV4)
        #expect(defaultModel is AnthropicMessagesLanguageModelV4)
        #expect(knownModelIds.isSuperset(of: [
            "claude-sonnet-5",
            "claude-fable-5",
            "claude-opus-4-8",
            "claude-opus-4-7",
            "claude-opus-4-6",
            "claude-sonnet-4-6",
        ]))
    }

    @Test("models with direct xhigh support preserve explicit xhigh effort")
    func directXhighModelsPreserveExplicitEffort() async throws {
        for modelId in [
            "claude-sonnet-5",
            "claude-fable-5",
            "claude-opus-4-8",
            "claude-opus-4-7",
        ] {
            let capture = AnthropicV4RequestCapture()
            let model = try makeAnthropicV4Model(modelId: modelId, capture: capture)

            _ = try await model.doGenerate(options: .init(
                prompt: anthropicV4TestPrompt,
                providerOptions: ["anthropic": ["effort": .string("xhigh")]]
            ))

            let request = decodeAnthropicV4Request(await capture.current())
            let outputConfig = request?["output_config"] as? [String: Any]
            #expect(outputConfig?["effort"] as? String == "xhigh")
        }
    }

    @Test("all current maximum-effort models preserve explicit max effort")
    func maximumEffortModelsPreserveExplicitMax() async throws {
        for modelId in [
            "claude-sonnet-5",
            "claude-fable-5",
            "claude-opus-4-8",
            "claude-opus-4-7",
            "claude-opus-4-6",
            "claude-sonnet-4-6",
        ] {
            let capture = AnthropicV4RequestCapture()
            let model = try makeAnthropicV4Model(modelId: modelId, capture: capture)

            _ = try await model.doGenerate(options: .init(
                prompt: anthropicV4TestPrompt,
                providerOptions: ["anthropic": ["effort": .string("max")]]
            ))

            let request = decodeAnthropicV4Request(await capture.current())
            let outputConfig = request?["output_config"] as? [String: Any]
            #expect(outputConfig?["effort"] as? String == "max")
        }
    }

    @Test("frontier models map top-level xhigh to adaptive xhigh")
    func frontierModelsMapXhighReasoning() async throws {
        for modelId in [
            "claude-sonnet-5",
            "claude-fable-5",
            "claude-opus-4-8",
            "claude-opus-4-7",
        ] {
            let capture = AnthropicV4RequestCapture()
            let model = try makeAnthropicV4Model(modelId: modelId, capture: capture)

            let result = try await model.doGenerate(options: .init(
                prompt: anthropicV4TestPrompt,
                reasoning: .xhigh
            ))

            let request = decodeAnthropicV4Request(await capture.current())
            let thinking = request?["thinking"] as? [String: Any]
            let outputConfig = request?["output_config"] as? [String: Any]
            #expect(thinking?["type"] as? String == "adaptive")
            #expect(outputConfig?["effort"] as? String == "xhigh")
            #expect(result.warnings.isEmpty)
        }
    }

    @Test("4.6 models map top-level xhigh to max with compatibility warning")
    func version46ModelsMapXhighReasoningToMax() async throws {
        for modelId in ["claude-opus-4-6", "claude-sonnet-4-6"] {
            let capture = AnthropicV4RequestCapture()
            let model = try makeAnthropicV4Model(modelId: modelId, capture: capture)

            let result = try await model.doGenerate(options: .init(
                prompt: anthropicV4TestPrompt,
                reasoning: .xhigh
            ))

            let request = decodeAnthropicV4Request(await capture.current())
            let thinking = request?["thinking"] as? [String: Any]
            let outputConfig = request?["output_config"] as? [String: Any]
            #expect(thinking?["type"] as? String == "adaptive")
            #expect(outputConfig?["effort"] as? String == "max")
            #expect(result.warnings.contains { warning in
                guard case let .compatibility(feature, details) = warning else { return false }
                return feature == "reasoning"
                    && details == "reasoning \"xhigh\" is not directly supported by this model. mapped to effort \"max\"."
            })
        }
    }

    @Test("older models map top-level xhigh to a 90 percent thinking budget")
    func olderModelsMapXhighReasoningToBudget() async throws {
        let capture = AnthropicV4RequestCapture()
        let model = try makeAnthropicV4Model(modelId: "claude-sonnet-4-5", capture: capture)

        _ = try await model.doGenerate(options: .init(
            prompt: anthropicV4TestPrompt,
            reasoning: .xhigh
        ))

        let request = decodeAnthropicV4Request(await capture.current())
        let thinking = request?["thinking"] as? [String: Any]
        #expect(thinking?["type"] as? String == "enabled")
        #expect(thinking?["budget_tokens"] as? Int == 57_600)
    }

    @Test("explicit max effort takes precedence over top-level reasoning")
    func explicitMaxTakesPrecedence() async throws {
        let capture = AnthropicV4RequestCapture()
        let model = try makeAnthropicV4Model(modelId: "claude-sonnet-5", capture: capture)

        _ = try await model.doGenerate(options: .init(
            prompt: anthropicV4TestPrompt,
            reasoning: .high,
            providerOptions: ["anthropic": ["effort": .string("max")]]
        ))

        let request = decodeAnthropicV4Request(await capture.current())
        let outputConfig = request?["output_config"] as? [String: Any]
        #expect(outputConfig?["effort"] as? String == "max")
        #expect(request?["thinking"] == nil)
    }

    @Test("V4 Anthropic file references serialize as file sources")
    func serializesProviderFileReference() async throws {
        let capture = AnthropicV4RequestCapture()
        let model = try makeAnthropicV4Model(modelId: "claude-sonnet-5", capture: capture)
        let prompt: LanguageModelV4Prompt = [
            .user(content: [
                .file(.init(
                    data: .reference(["anthropic": "file_123"]),
                    mediaType: "application/pdf",
                    filename: "guide.pdf"
                ))
            ], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        let request = decodeAnthropicV4Request(await capture.current())
        let messages = request?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        let source = content?.first?["source"] as? [String: Any]
        #expect(content?.first?["type"] as? String == "document")
        #expect(source?["type"] as? String == "file")
        #expect(source?["file_id"] as? String == "file_123")
        #expect(anthropicV4BetaSet(await capture.current()).contains("files-api-2025-04-14"))
    }

    @Test("V4 Anthropic file references support container uploads")
    func serializesContainerUploadReference() async throws {
        let capture = AnthropicV4RequestCapture()
        let model = try makeAnthropicV4Model(modelId: "claude-sonnet-5", capture: capture)
        let prompt: LanguageModelV4Prompt = [
            .user(content: [
                .file(.init(
                    data: .reference(["anthropic": "file_456"]),
                    mediaType: "application/pdf",
                    providerOptions: ["anthropic": ["containerUpload": .bool(true)]]
                ))
            ], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        let request = decodeAnthropicV4Request(await capture.current())
        let messages = request?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        #expect(content?.first?["type"] as? String == "container_upload")
        #expect(content?.first?["file_id"] as? String == "file_456")
        #expect(content?.first?["source"] == nil)
    }
}
