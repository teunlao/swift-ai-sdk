import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

@Suite("OpenAI-compatible thought signatures")
struct OpenAICompatibleThoughtSignatureV4Tests {
    private let prompt: LanguageModelV4Prompt = [
        .user(
            content: [.text(LanguageModelV4TextPart(text: "Hello"))],
            providerOptions: nil
        )
    ]

    private func makeHTTPResponse(url: URL, contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
    }

    @Test("empty response signatures do not create provider metadata")
    func emptyResponseSignaturesAreOmitted() async throws {
        let generateResponse: [String: Any] = [
            "choices": [[
                "message": [
                    "tool_calls": [[
                        "id": "call-1",
                        "function": ["name": "lookup", "arguments": "{}"],
                        "extra_content": ["google": ["thought_signature": ""]]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ]
        let generateData = try JSONSerialization.data(withJSONObject: generateResponse)
        let streamEvent = #"{"choices":[{"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call-1","type":"function","function":{"name":"lookup","arguments":"{}"},"extra_content":{"google":{"thought_signature":""}}}]},"finish_reason":"tool_calls"}]}"#
        let url = URL(string: "https://api.example.com/chat/completions")!

        let fetch: FetchFunction = { request in
            let isStream = request.httpBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }?["stream"] as? Bool == true

            if isStream {
                return FetchResponse(
                    body: .stream(AsyncThrowingStream { continuation in
                        continuation.yield(Data("data: \(streamEvent)\n\n".utf8))
                        continuation.yield(Data("data: [DONE]\n\n".utf8))
                        continuation.finish()
                    }),
                    urlResponse: makeHTTPResponse(url: url, contentType: "text/event-stream")
                )
            }

            return FetchResponse(
                body: .data(generateData),
                urlResponse: makeHTTPResponse(url: url, contentType: "application/json")
            )
        }

        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://api.example.com",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.languageModel(modelId: "chat-model")

        let generated = try await model.doGenerate(options: .init(prompt: prompt))
        let generatedToolCalls = generated.content.compactMap { content -> LanguageModelV4ToolCall? in
            guard case .toolCall(let toolCall) = content else { return nil }
            return toolCall
        }
        #expect(generatedToolCalls.count == 1)
        #expect(generatedToolCalls[0].providerMetadata == nil)

        let streamed = try await model.doStream(options: .init(prompt: prompt))
        var streamedToolCalls: [LanguageModelV4ToolCall] = []
        for try await part in streamed.stream {
            if case .toolCall(let toolCall) = part {
                streamedToolCalls.append(toolCall)
            }
        }
        #expect(streamedToolCalls.count == 1)
        #expect(streamedToolCalls[0].providerMetadata == nil)
    }
}
