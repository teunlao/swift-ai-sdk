import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

@Suite("Azure default Responses requests")
struct AzureResponsesInputTests {
    struct Route: Sendable {
        let foundry: Bool
        let binding: String
    }
    private actor Capture {
        var request: URLRequest?
        func respond(_ request: URLRequest) -> FetchResponse {
            self.request = request
            let body = request.url!.path.hasSuffix("/chat/completions")
                ? #"{"id":"chat","created":1,"model":"gpt-4.1","choices":[{"index":0,"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
                : #"{"id":"resp","output":[{"type":"message","role":"assistant","id":"msg","content":[{"type":"output_text","text":"answer","annotations":[]}]}],"usage":{"input_tokens":1,"output_tokens":1}}"#
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!)
        }
        func value() -> URLRequest? { request }
    }

    @Test("Default bindings use Responses and Foundry tags message items", arguments: [
        Route(foundry: true, binding: "call"), Route(foundry: false, binding: "language"), Route(foundry: true, binding: "responses")
    ])
    func defaultInput(route: Route) async throws {
        let capture = Capture()
        let base = route.foundry
            ? "https://resource.services.ai.azure.com/api/projects/project/openai"
            : "https://resource.openai.azure.com/openai"
        let provider = try createAzure(settings: .init(baseURL: base, apiKey: "key", fetch: { await capture.respond($0) }))
        let model: any LanguageModelV4
        switch route.binding {
        case "call": model = try provider("gpt-4.1")
        case "language": model = try provider.languageModel(modelId: "gpt-4.1")
        default: model = provider.responses("gpt-4.1")
        }
        let result = try await model.doGenerate(options: .init(prompt: [
            .system(content: "system", providerOptions: nil),
            .user(content: [.text(.init(text: "user"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "prior"))], providerOptions: nil)
        ]))
        #expect(result.content.contains { if case .text(let text) = $0 { return text.text == "answer" }; return false })
        let request = try #require(await capture.value())
        #expect(request.url?.absoluteString == base + "/v1/responses" + (route.foundry ? "" : "?api-version=v1"))
        let data = try #require(request.httpBody)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let body) = json, case .array(let input)? = body["input"] else {
            Issue.record("Expected Responses input"); return
        }
        var expected: [[String: JSONValue]] = [
            ["role": .string("system"), "content": .string("system")],
            ["role": .string("user"), "content": .array([.object(["type": .string("input_text"), "text": .string("user")])])],
            ["role": .string("assistant"), "content": .string("prior")]
        ]
        if route.foundry { expected = expected.map { $0.merging(["type": .string("message")]) { _, new in new } } }
        #expect(input == expected.map(JSONValue.object))
    }
}
