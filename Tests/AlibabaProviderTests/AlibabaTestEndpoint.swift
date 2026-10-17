import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AlibabaProvider

let alibabaTestPrompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
let alibabaTestResponse: JSONObject = ["id": "chat-1", "created": 1000, "model": "qwen-plus", "choices": [["index": 0, "message": ["role": "assistant", "content": "Answer"], "finish_reason": "stop"]]]

actor AlibabaTestEndpoint {
    private var response: JSONValue
    private var events: [JSONValue]?
    private var requests: [URLRequest] = []
    init(_ response: JSONValue = .object(alibabaTestResponse), events: [JSONValue]? = nil) { self.response = response; self.events = events }
    func fetch(_ request: URLRequest) throws -> FetchResponse {
        requests.append(request)
        let body: ProviderHTTPResponseBody
        if let events {
            let chunks = try events.map { Data("data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n".utf8) }
            body = .stream(AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            })
        } else { body = .data(try JSONEncoder().encode(response)) }
        return FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": events == nil ? "application/json" : "text/event-stream", "X-Response": "response"])!)
    }
    func body() throws -> JSONObject {
        let request = try #require(requests.last)
        return try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
    }
    func request() throws -> URLRequest { try #require(requests.last) }
}
func alibabaTestModel(_ endpoint: AlibabaTestEndpoint, id: AlibabaChatModelId = .qwenPlus, includeUsage: Bool = true) -> AlibabaChatLanguageModel {
    createAlibaba(settings: .init(apiKey: "key", fetch: { request in try await endpoint.fetch(request) }, includeUsage: includeUsage)).languageModel(id)
}
func collectAlibaba(_ stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>) async throws -> [LanguageModelV4StreamPart] {
    var parts: [LanguageModelV4StreamPart] = []
    for try await part in stream { parts.append(part) }
    return parts
}
