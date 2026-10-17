import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

@Suite("Compatible resolved headers")
struct OpenAICompatibleHeadersTests {
    actor Credentials {
        var token = "first"
        func update() { token = "second" }
        func headers() -> [String: String] { ["authorization": "Bearer \(token)", "X-Token": token] }
    }
    actor Requests {
        var authorizations: [String] = []
        var tokens: [String] = []
        func store(_ request: URLRequest) {
            authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            tokens.append(request.value(forHTTPHeaderField: "X-Token") ?? "")
        }
        func value() -> ([String], [String]) { (authorizations, tokens) }
    }
    @Test func asyncHeadersRefreshAndRequestOverridesRemainAuthoritative() async throws {
        let credentials = Credentials()
        let requests = Requests()
        let fetch: FetchFunction = { request in
            await requests.store(request)
            let data = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            guard case .object(let body) = data else { throw CancellationError() }
            #expect(body["vendor_mode"] == true)
            return FetchResponse(body: .data(Data(#"{"choices":[{"message":{"content":"Answer"},"finish_reason":"stop"}]}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createOpenAICompatible(settings: .init(
            baseURL: "https://api.example.com", name: "custom", apiKey: "fallback", headers: .resolve { await credentials.headers() }, fetch: fetch,
            transformRequestBody: { body, warnings in
                warnings.append(.compatibility(feature: "vendor-mode", details: "Enabled vendor mode."))
                var body = body
                body["vendor_mode"] = true
                return body
            }
        ))("model")
        let first = try await model.doGenerate(options: .init(prompt: []))
        await credentials.update()
        let second = try await model.doGenerate(options: .init(prompt: [], headers: ["Authorization": "request"]))
        let values = await requests.value()
        #expect(values.0 == ["Bearer first", "request"])
        #expect(values.1 == ["first", "second"])
        for result in [first, second] {
            #expect(result.warnings.contains { if case .compatibility(feature: "vendor-mode", details: _) = $0 { return true }; return false })
        }
    }
}
