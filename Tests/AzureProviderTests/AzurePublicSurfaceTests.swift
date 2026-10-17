import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

private func azureResponse(_ request: URLRequest, body: String) -> FetchResponse {
    FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200,
        httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
}

@Suite("Azure public exports")
struct AzurePublicSurfaceTests {
    @Test("Azure search factories produce real Responses tool requests and provider results", arguments: [false, true])
    func search(_ preview: Bool) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
            let type = preview ? "web_search_preview" : "web_search"
            var tool: JSONObject = ["type": .string(type), "search_context_size": .string(preview ? "medium" : "high"),
                "user_location": ["type": "approximate", "country": .string(preview ? "NL" : "US")]]
            if !preview {
                tool["external_web_access"] = false
                tool["filters"] = ["allowed_domains": ["example.com"], "blocked_domains": ["blocked.example"]]
            }
            #expect(body["tools"] == .array([.object(tool)]))
            #expect(body["tool_choice"] == ["type": .string(type)])
            return azureResponse(request, body: #"{"id":"resp:search","output":[{"type":"web_search_call","id":"search:opaque","status":"completed","action":{"type":"search","query":"sdk"}}]}"#)
        }))
        let tool = preview
            ? provider.tools.webSearchPreview(.init(searchContextSize: "medium", userLocation: .init(country: "NL")))
            : provider.tools.webSearch(.init(filters: .init(allowedDomains: ["example.com"], blockedDomains: ["blocked.example"]),
                externalWebAccess: false, searchContextSize: "high", userLocation: .init(country: "US")))
        let result = try await provider.responses("deployment").doGenerate(options: .init(prompt: [],
            tools: [.provider(.init(id: try #require(tool.id), name: "lookup", args: tool.args ?? [:]))], toolChoice: .tool(toolName: "lookup")))
        let call = try #require(result.content.compactMap { if case .toolCall(let value) = $0 { return value }; return nil }.first)
        let output = try #require(result.content.compactMap { if case .toolResult(let value) = $0 { return value }; return nil }.first)
        #expect(call.toolCallId == "search:opaque")
        #expect(call.toolName == "lookup")
        #expect(call.providerExecuted == true)
        #expect(output.toolName == "lookup")
        #expect(output.result == ["action": ["type": "search", "query": "sdk"]])
    }

    @Test("Canonical Chat options are exported through Azure and reach the Chat HTTP owner")
    func chatOptions() async throws {
        let options = OpenAILanguageModelChatOptions(reasoningEffort: .max, store: false,
            promptCacheOptions: .init(mode: .explicit, ttl: .thirtyMinutes))
        let value = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(options))
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
            #expect(body["reasoning_effort"] == "max")
            #expect(body["store"] == false)
            #expect(body["prompt_cache_options"] == ["mode": "explicit", "ttl": "30m"])
            return azureResponse(request, body: #"{"id":"chat","created":0,"model":"gpt-5.6","choices":[{"index":0,"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}]}"#)
        }))
        let result = try await provider.chat("gpt-5.6").doGenerate(options: .init(prompt: [], providerOptions: ["openai": value]))
        #expect(result.content.contains { if case .text(let value) = $0 { return value.text == "answer" }; return false })
    }

    @Test("Whole Responses metadata contracts decode actual Azure response and content metadata")
    func metadata() async throws {
        let options = OpenAILanguageModelResponsesOptions(previousResponseId: "previous:opaque", reasoningEffort: "high", reasoningSummary: "detailed", store: false, forceReasoning: true)
        let value = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(options))
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
            #expect(body["previous_response_id"] == "previous:opaque")
            #expect(body["store"] == false)
            #expect(body["reasoning"] == ["effort": "high", "summary": "detailed"])
            return azureResponse(request, body: #"{"id":"resp:metadata","service_tier":"priority","output":[{"type":"reasoning","id":"reasoning:opaque","encrypted_content":null,"summary":[{"type":"summary_text","text":"Reasoning"}]},{"type":"message","id":"message:opaque","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Answer","annotations":[{"type":"file_citation","file_id":"file:opaque","filename":"notes.txt","index":1.5}]}]}]}"#)
        }))
        let result = try await provider.responses("deployment").doGenerate(options: .init(prompt: [], providerOptions: ["azure": value]))
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(AzureResponsesProviderMetadata.self, from: JSONEncoder().encode(result.providerMetadata))
        #expect(metadata.azure.responseId == "resp:metadata")
        #expect(metadata.azure.serviceTier == "priority")
        let reasoning = try #require(result.content.compactMap { if case .reasoning(let value) = $0 { return value }; return nil }.first)
        let reasoningMetadata = try decoder.decode(AzureResponsesReasoningProviderMetadata.self, from: JSONEncoder().encode(reasoning.providerMetadata))
        #expect(reasoningMetadata.azure.itemId == "reasoning:opaque")
        #expect(reasoningMetadata.azure.reasoningEncryptedContent == nil)
        let text = try #require(result.content.compactMap { if case .text(let value) = $0 { return value }; return nil }.first)
        let textMetadata = try decoder.decode(AzureResponsesTextProviderMetadata.self, from: JSONEncoder().encode(text.providerMetadata))
        #expect(textMetadata.azure.itemId == "message:opaque")
        #expect(textMetadata.azure.phase == .finalAnswer)
        #expect(textMetadata.azure.annotations?.count == 1)
        let source = try #require(result.content.compactMap { if case .source(let value) = $0 { return value }; return nil }.first)
        guard case .document(_, _, _, _, let providerMetadata) = source else { Issue.record("Expected a document source"); return }
        let sourceMetadata = try decoder.decode(AzureResponsesSourceDocumentProviderMetadata.self, from: JSONEncoder().encode(providerMetadata))
        #expect(sourceMetadata.azure == .fileCitation(fileId: "file:opaque", index: 1.5))
    }
}
