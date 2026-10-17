import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import CohereProvider

@Suite("Cohere tool HTTP boundaries")
struct CoherePrepareToolsTests {
    @Test("function tools, named selection, and external tool-choice values", arguments: ["auto", "none", "required", "named", "empty", "unsupported"])
    func tools(mode: String) async throws {
        let recorder = RequestRecorder()
        let provider = createCohere(settings: .init(apiKey: "key", fetch: { request in
            await recorder.record(request)
            return FetchResponse(body: .data(Data(#"{"message":{"role":"assistant"},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":0,"output_tokens":0}}}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        var tools: [LanguageModelV4Tool] = [
            .function(.init(name: "first", inputSchema: ["type": "object"], description: "description", strict: true)),
            .function(.init(name: "second", inputSchema: ["type": "object"]))
        ]
        let choice: LanguageModelV4ToolChoice?
        switch mode {
        case "auto": choice = .auto
        case "none": choice = LanguageModelV4ToolChoice.none
        case "required": choice = .required
        case "named": choice = .tool(toolName: "second")
        case "empty": tools = []; choice = .required
        default: tools = [.provider(.init(id: "provider.tool", name: "custom", args: [:]))]; choice = nil
        }
        let result = try await provider.languageModel(.commandRPlus).doGenerate(options: .init(prompt: [], tools: tools, toolChoice: choice))
        let request = try #require(await recorder.first())
        let body = try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
        let first: JSONValue = ["type": "function", "function": ["name": "first", "description": "description", "parameters": ["type": "object"]]]
        let second: JSONValue = ["type": "function", "function": ["name": "second", "parameters": ["type": "object"]]]
        switch mode {
        case "empty":
            #expect(body["tools"] == nil)
            #expect(body["tool_choice"] == nil)
        case "unsupported":
            #expect(body["tools"] == [])
            #expect(result.warnings == [.unsupported(feature: "provider-defined tool provider.tool", details: nil)])
        case "named":
            #expect(body["tools"] == [second])
            #expect(body["tool_choice"] == "REQUIRED")
        default:
            #expect(body["tools"] == [first, second])
            if mode == "auto" { #expect(body["tool_choice"] == nil) }
            else { #expect(body["tool_choice"] == .string(mode == "none" ? "NONE" : "REQUIRED")) }
        }
    }
}
