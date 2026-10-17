import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenResponsesProvider

@Suite("Open Responses provider boundaries")
struct OpenResponsesProviderTests {
    private final class HeaderState: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> [String: String] {
            lock.lock(); defer { lock.unlock() }
            count += 1
            return ["Authorization": "Bearer rotated-\(count)"]
        }
    }

    @Test("optional and empty keys omit Authorization while retaining default integration UA", arguments: [Optional<String>.none, ""])
    func optionalKey(key: String?) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", apiKey: key, fetch: { request in try await endpoint.fetch(request) }))
        let result = try await provider("model").doGenerate(options: .init(prompt: openResponsesTestPrompt))
        let request = try #require(await endpoint.allRequests().first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-open-responses/\(OPEN_RESPONSES_VERSION)") == true)
        #expect(result.finishReason.unified == .stop)
    }

    @Test("dynamic headers resolve only per API request and caller headers merge")
    func dynamicHeaders() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let state = HeaderState()
        let provider = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", apiKey: "fixed", headers: .dynamic { state.next() }, fetch: { request in try await endpoint.fetch(request) }, userAgentSuffix: "endpoint-sdk/1"))
        let model = provider("model")
        _ = try await model.doGenerate(options: .init(prompt: openResponsesTestPrompt, headers: ["X-Request": "request"]))
        _ = try await model.doGenerate(options: .init(prompt: openResponsesTestPrompt))
        let requests = await endpoint.allRequests()
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer rotated-1", "Bearer rotated-2"])
        #expect(requests[0].value(forHTTPHeaderField: "X-Request") == "request")
        #expect(requests[0].value(forHTTPHeaderField: "User-Agent")?.contains("endpoint-sdk/1") == true)
        #expect(requests[0].url?.absoluteString == openResponsesTestURL)
    }

    @Test("endpoint error callbacks run before missing-output fallback and preserve provider data", arguments: [false, true])
    func generationError(configured: Bool) async throws {
        let payload: JSONValue = ["code": "busy", "message": "Try again later", "http_status": 503, "retry": false, "status_code": 503]
        let endpoint = OpenResponsesTestEndpoint(["error": payload, "status": "failed"])
        let callback: (@Sendable (OpenResponsesResponseError) throws -> OpenResponsesResponseErrorMetadata)? = configured ? { @Sendable error in
            let code = { if case .number(let value) = error.fields["http_status"] { return Int(exactly: value) }; return nil }()
            let retry: Bool? = { if case .bool(let value) = error.fields["retry"] { return value }; return nil }()
            return .init(statusCode: code, isRetryable: retry)
        } : nil
        let provider = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", fetch: { request in try await endpoint.fetch(request) }, getResponseErrorMetadata: callback))
        do {
            _ = try await provider("model").doGenerate(options: .init(prompt: openResponsesTestPrompt))
            Issue.record("Expected response error")
        } catch let error as APICallError {
            #expect(error.message == "Try again later")
            #expect(error.statusCode == (configured ? 503 : 400))
            #expect(error.isRetryable == false)
            #expect(try jsonValue(from: #require(error.data)) == payload)
        }
    }

    @Test("response error metadata applies identically to failed and error stream events", arguments: ["response.failed", "error"])
    func streamError(type: String) async throws {
        let error: JSONValue = ["code": "busy", "message": "Try again later", "http_status": 503, "retry": false]
        let event: JSONValue = type == "error" ? ["type": "error", "error": error] : ["type": "response.failed", "response": ["status": "failed", "error": error]]
        let endpoint = OpenResponsesTestEndpoint()
        try await endpoint.setEvents([event])
        let provider = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", fetch: { request in try await endpoint.fetch(request) }, getResponseErrorMetadata: { value in
            let code = { if case .number(let value) = value.fields["http_status"] { return Int(exactly: value) }; return nil }()
            return .init(statusCode: code, isRetryable: false)
        }))
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: openResponsesTestPrompt)))
        let errors = parts.compactMap { part -> ProviderStreamError? in if case .error(.providerStreamError(let value)) = part { return value }; return nil }
        #expect(errors == [.init(message: "Try again later", type: type, code: .string("busy"), statusCode: 503, isRetryable: false, data: event)])
        guard case .finish(let finish, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish == .init(unified: .error, raw: "busy"))
    }

    @Test("default HTTP error parsing preserves nullable fields and custom failed handlers are used")
    func failedHandlers() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        await endpoint.setResponse(["error": ["message": "Denied", "type": .null, "param": .null, "code": .null]], status: 403)
        let provider = try openResponsesProvider(endpoint)
        do {
            _ = try await provider("model").doGenerate(options: .init(prompt: []))
            Issue.record("Expected HTTP failure")
        } catch let error as APICallError {
            #expect(error.message == "Denied")
            let parsed = try #require(error.data as? OpenResponsesErrorData)
            let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(parsed))
            #expect(encoded == ["error": ["message": "Denied", "type": .null, "param": .null, "code": .null]])
        }
        let custom = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", fetch: { request in try await endpoint.fetch(request) }, failedResponseHandler: { input in
            .init(value: APICallError(message: "Mapped HTTP failure", url: input.url, requestBodyValues: input.requestBodyValues, statusCode: input.response.statusCode), responseHeaders: [:])
        }))
        do {
            _ = try await custom("model").doGenerate(options: .init(prompt: []))
            Issue.record("Expected custom HTTP failure")
        } catch let error as APICallError {
            #expect(error.message == "Mapped HTTP failure")
            #expect(error.statusCode == 403)
        }
    }
}
