import Foundation
import Testing
@testable import OpenAICompatibleProvider
import AISDKProvider
import AISDKProviderUtils

private let transformTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private actor RequestCapture {
    private var request: URLRequest?
    func store(_ request: URLRequest) { self.request = request }
    func current() -> URLRequest? { request }
}

private func makeHTTPResponse(url: URL, contentType: String) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    )!
}

private func makeMinimalChatResponseData() throws -> Data {
    let response: [String: Any] = [
        "id": "chatcmpl-test",
        "created": 1_700_000_000,
        "model": "grok-beta",
        "choices": [[
            "message": ["content": "Hi"],
            "finish_reason": "stop"
        ]],
        "usage": [
            "prompt_tokens": 1,
            "completion_tokens": 1,
            "total_tokens": 2,
        ],
    ]
    return try JSONSerialization.data(withJSONObject: response)
}

@Suite("OpenAICompatible transformRequestBody", .serialized)
struct OpenAICompatibleTransformRequestBodyTests {
    @Test("applies transformRequestBody in doGenerate")
    func appliesTransformInDoGenerate() async throws {
        let capture = RequestCapture()
        let url = URL(string: "https://api.example.com/v1/chat/completions")!
        let responseData = try makeMinimalChatResponseData()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url, contentType: "application/json"))
        }

        let provider = createOpenAICompatibleProvider(settings: .init(
            baseURL: "https://api.example.com/v1",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch,
            transformRequestBody: { body in
                var updated = body
                updated["transformed"] = .bool(true)
                return updated
            }
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(options: .init(prompt: transformTestPrompt))

        let captured = await capture.current()
        let bodyData = try #require(captured?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)
        #expect(body["transformed"] == .bool(true))
    }

    @Test("applies transformRequestBody in doStream")
    func appliesTransformInDoStream() async throws {
        let capture = RequestCapture()
        let url = URL(string: "https://api.example.com/v1/chat/completions")!

        let sse = """
        data: {\"id\":\"chatcmpl-1\",\"created\":1712000000,\"model\":\"grok-beta\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}

        data: [DONE]

        """
        let data = Data(sse.utf8)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: makeHTTPResponse(url: url, contentType: "text/event-stream"))
        }

        let provider = createOpenAICompatibleProvider(settings: .init(
            baseURL: "https://api.example.com/v1",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch,
            transformRequestBody: { body in
                var updated = body
                updated["transformed"] = .bool(true)
                return updated
            }
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: .init(prompt: transformTestPrompt))

        for try await _ in result.stream {
            // exhaust stream
        }

        let captured = await capture.current()
        let bodyData = try #require(captured?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)
        #expect(body["stream"] == .bool(true))
        #expect(body["transformed"] == .bool(true))
    }
}

