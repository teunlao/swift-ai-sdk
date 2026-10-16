import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import ReplicateProvider

@Suite("Replicate image editing and prediction lifecycle")
struct ReplicateEditingTests {
    private actor Requests {
        var values: [URLRequest] = []
        func record(_ request: URLRequest) { values.append(request) }
        func all() -> [URLRequest] { values }
    }

    @Test("image editing maps files and mask and reserves synchronous wait controls", arguments: ["black-forest-labs/flux-fill-pro", "black-forest-labs/flux-2-pro"])
    func editing(_ id: String) async throws {
        let requests = Requests()
        let fetch: FetchFunction = { request in
            await requests.record(request)
            let data = request.httpMethod == "POST" ? Data(#"{"status":"succeeded","output":["https://cdn.example.com/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/id"}}"#.utf8) : Data([1])
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": request.httpMethod == "POST" ? "application/json" : "image/png"])!)
        }
        let model = createReplicate(settings: .init(apiToken: "token", fetch: fetch)).image(.init(rawValue: id))
        let result = try await model.doGenerate(options: .init(prompt: "Edit", n: 1,
            files: [.file(mediaType: "image/png", data: .binary(Data([1])), providerOptions: nil), .url(url: "https://example.com/reference.png", providerOptions: nil)],
            mask: .url(url: "https://example.com/mask.png", providerOptions: nil),
            providerOptions: ["replicate": ["maxWaitTimeInSeconds": .number(30), "pollIntervalMillis": .number(1), "maxPollAttempts": .number(1), "custom": .bool(true)]]
        ))
        let request = try #require(await requests.all().first)
        #expect(request.value(forHTTPHeaderField: "Prefer") == "wait=30")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        let expected: [String: JSONValue] = id.contains("flux-2")
            ? ["prompt": .string("Edit"), "num_outputs": .number(1), "input_image": .string("data:image/png;base64,AQ=="), "input_image_2": .string("https://example.com/reference.png"), "custom": .bool(true)]
            : ["prompt": .string("Edit"), "num_outputs": .number(1), "image": .string("data:image/png;base64,AQ=="), "mask": .string("https://example.com/mask.png"), "custom": .bool(true)]
        #expect(body == .object(["input": .object(expected)]))
        #expect(result.images == .binary([Data([1])]))
        #expect(result.warnings.count == 1)
    }

    @Test("unfinished synchronous predictions are polled before downloading")
    func polling() async throws {
        let requests = Requests()
        let fetch: FetchFunction = { request in
            await requests.record(request)
            let json: String
            if request.httpMethod == "POST" {
                json = #"{"status":"processing","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/id"}}"#
            } else if request.url!.host == "api.replicate.com" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
                #expect(request.value(forHTTPHeaderField: "X-Request") == "value")
                json = #"{"status":"succeeded","output":"https://cdn.example.com/image.png","urls":{"get":"https://api.replicate.com/v1/predictions/id"}}"#
            } else {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                return FetchResponse(body: .data(Data([2])), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
            }
            return FetchResponse(body: .data(Data(json.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createReplicate(settings: .init(apiToken: "token", fetch: fetch)).image("black-forest-labs/flux-schnell")
        let result = try await model.doGenerate(options: .init(n: 1, providerOptions: ["replicate": ["maxPollAttempts": .number(1)]], headers: ["X-Request": "value"]))
        #expect(result.images == .binary([Data([2])]))
    }

    @Test("failed predictions and exhausted polling surface invalid response errors", arguments: ["failed", "processing", "succeeded"])
    func failure(_ status: String) async throws {
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(Data(#"{"status":"\#(status)","error":"Rejected","urls":{"get":"https://api.replicate.com/v1/predictions/id"}}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createReplicate(settings: .init(apiToken: "token", fetch: fetch)).image("black-forest-labs/flux-schnell")
        await #expect(throws: InvalidResponseDataError.self) {
            try await model.doGenerate(options: .init(n: 1, providerOptions: ["replicate": ["maxPollAttempts": .number(1)]]))
        }
    }

    @Test("invalid wait duration is rejected before the API request")
    func invalidOptions() async throws {
        let model = createReplicate(settings: .init(apiToken: "token")).image("black-forest-labs/flux-schnell")
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(n: 1, providerOptions: ["replicate": ["maxWaitTimeInSeconds": .number(0)]]))
        }
    }
}
