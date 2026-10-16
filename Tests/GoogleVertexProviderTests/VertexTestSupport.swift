import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

actor VertexRequests {
    private(set) var values: [URLRequest] = []
    func append(_ request: URLRequest) { values.append(request) }
    var last: URLRequest? { values.last }
}

func vertexResponse(_ request: URLRequest, _ json: String, status: Int = 200) throws -> FetchResponse {
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                              headerFields: ["Content-Type": "application/json", "x-request-id": "vertex-request"]))
    return FetchResponse(body: .data(Data(json.utf8)), urlResponse: response)
}

func vertexBody(_ request: URLRequest) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
}

func vertexFixture(_ name: String) throws -> String {
    let root = try #require(Bundle.module.resourceURL)
    return try String(contentsOf: root.appendingPathComponent("Fixtures").appendingPathComponent(name), encoding: .utf8)
}

func vertexProvider(_ fetch: @escaping FetchFunction) -> GoogleVertexProvider {
    createGoogleVertex(settings: .init(fetch: fetch, baseURL: "https://vertex.example/"))
}
