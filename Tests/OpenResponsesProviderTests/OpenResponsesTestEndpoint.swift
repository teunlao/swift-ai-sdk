import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenResponsesProvider

let openResponsesTestURL = "https://endpoint.example/v1/responses"
let openResponsesTestPrompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]

func openResponsesTestResponse(output: [JSONValue] = [], usage: JSONValue? = nil) -> JSONObject {
    var value: JSONObject = ["id": "response", "created_at": 1000, "model": "model", "status": "completed", "output": .array(output)]
    if let usage { value["usage"] = usage }
    return value
}

actor OpenResponsesTestEndpoint {
    private var response: JSONValue
    private var status = 200
    private var lines: [String]?
    private var requests: [URLRequest] = []
    init(_ response: JSONObject = openResponsesTestResponse()) { self.response = .object(response) }
    func setResponse(_ response: JSONObject, status: Int = 200) { self.response = .object(response); self.status = status; lines = nil }
    func setEvents(_ events: [JSONValue]) throws { lines = try events.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }; status = 200 }
    func setLines(_ values: [String]) { lines = values; status = 200 }
    func allRequests() -> [URLRequest] { requests }
    func lastBody() throws -> JSONObject {
        let request = try #require(requests.last)
        return try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
    }
    func fetch(_ request: URLRequest) throws -> FetchResponse {
        requests.append(request)
        let body: ProviderHTTPResponseBody
        if let lines {
            let bytes = lines.map { Data("data: \($0)\n\n".utf8) }
            body = .stream(AsyncThrowingStream { continuation in
                for chunk in bytes { continuation.yield(chunk) }
                continuation.finish()
            })
        } else { body = .data(try JSONEncoder().encode(response)) }
        let url = try #require(request.url)
        return FetchResponse(body: body, urlResponse: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": lines == nil ? "application/json" : "text/event-stream", "X-Response": "response-value"])!)
    }
}

func openResponsesProvider(_ endpoint: OpenResponsesTestEndpoint, strict: Bool = false, extensions: [Experimental_OpenResponsesExtensionRegistration] = []) throws -> OpenResponsesProvider {
    try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", fetch: { request in try await endpoint.fetch(request) }, strictResponseInput: strict, experimentalExtensions: extensions))
}
func openResponsesCollect(_ result: LanguageModelV4StreamResult) async throws -> [LanguageModelV4StreamPart] {
    var values: [LanguageModelV4StreamPart] = []
    for try await value in result.stream { values.append(value) }
    return values
}
func openResponsesFixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")))
}

struct OpenResponsesTestExtension: Experimental_OpenResponsesExtension {
    var id = "acme.search"
    var toolType: Experimental_OpenResponsesNamespacedType?
    var itemTypes: [Experimental_OpenResponsesNamespacedType]?
    var eventTypes: [Experimental_OpenResponsesNamespacedType]?
    var encodeTool: Experimental_OpenResponsesToolEncoder?
    var encodeToolChoice: Experimental_OpenResponsesToolEncoder?
    var decodeItem: Experimental_OpenResponsesItemDecoder?
    var encodeInputItem: Experimental_OpenResponsesInputEncoder?
    var decodeEvent: Experimental_OpenResponsesEventDecoder?
}
