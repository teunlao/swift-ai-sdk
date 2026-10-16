import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

func googleFixture(_ filename: String) throws -> Data {
    let path = try #require(Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: path)
}
func googleResponse(_ request: URLRequest, data: Data, status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"]) throws -> FetchResponse {
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    return .init(body: .data(data), urlResponse: response)
}
func googleBody(_ request: URLRequest) throws -> JSONObject {
    let data = try #require(request.httpBody)
    guard case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: data) else { throw GoogleTestError.invalidBody }
    return body
}
func object(_ value: JSONValue?) -> JSONObject { if case .object(let object) = value { return object }; return [:] }
func array(_ value: JSONValue?) -> [JSONValue] { if case .array(let array) = value { return array }; return [] }
func string(_ value: JSONValue?) -> String? { if case .string(let text) = value { return text }; return nil }
func googleData(_ value: JSONValue) throws -> Data { try JSONEncoder().encode(value) }
func googleCollect(_ stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>) async throws -> [LanguageModelV4StreamPart] {
    var result: [LanguageModelV4StreamPart] = []
    for try await part in stream { result.append(part) }
    return result
}
let googlePrompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
enum GoogleTestError: Error { case invalidBody; case unexpectedRequest }

actor GoogleTransport {
    struct Reply: Sendable {
        let data: Data
        let status: Int
        let headers: [String: String]
        init(_ data: Data, status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"]) { self.data = data; self.status = status; self.headers = headers }
    }
    private var replies: [Reply]
    private var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func fetch(_ request: URLRequest) throws -> FetchResponse {
        guard !replies.isEmpty else { throw GoogleTestError.unexpectedRequest }
        requests.append(request)
        let reply = replies.removeFirst()
        return try googleResponse(request, data: reply.data, status: reply.status, headers: reply.headers)
    }
    func captured() -> [URLRequest] { requests }
    func provider() -> GoogleProvider {
        createGoogle(settings: .init(baseURL: "https://provider.example/v1beta/", apiKey: "test-key", headers: ["X-Provider": "configured"], fetch: { request in try await self.fetch(request) }, generateId: { "generated-id" }))
    }
}
