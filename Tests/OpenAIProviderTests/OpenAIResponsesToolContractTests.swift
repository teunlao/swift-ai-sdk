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

    @Test("File search preserves numeric limits on the HTTP boundary", arguments: [2.5, 1e20])
    func fileSearchNumericLimit(limit: Double) async throws {
        let capture = Capture()
        let result = try await provider(capture).responses("gpt-4.1").doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Search"))], providerOptions: nil)],
            tools: [.provider(.init(id: "openai.file_search", name: "documents", args: [
                "vectorStoreIds": .array([.string("vs_documents")]), "maxNumResults": .number(limit)
            ]))]
        ))
        #expect(result.finishReason.unified == .stop)
        let body = try #require(await capture.value())
        guard case .object(let object) = body, case .array(let tools)? = object["tools"],
              case .object(let tool)? = tools.first else { Issue.record("Missing file search wire tool"); return }
        #expect(tool["type"] == .string("file_search"))
        #expect(tool["max_num_results"] == .number(limit))
        #expect(tool["vector_store_ids"] == .array([.string("vs_documents")]))
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

    @Test("Reasoning mode and context reject explicit null", arguments: ["reasoningMode", "reasoningContext"])
    func reasoningOptionsRejectNull(key: String) async throws {
        let provider = try createOpenAI(settings: .init(apiKey: "test", fetch: { _ in throw URLError(.badServerResponse) }))
        await #expect(throws: InvalidArgumentError.self) {
            try await provider.responses("gpt-5.6-sol").doGenerate(options: .init(
                prompt: [], providerOptions: ["openai": [key: .null]]
            ))
        }
    }
}
