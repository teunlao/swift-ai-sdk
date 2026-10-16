import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import LumaProvider

@Suite("Luma image editing")
struct LumaImageModelTests {
    private actor Capture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func value() -> URLRequest? { request }
    }

    @Test("reference modes build Luma editing payloads", arguments: ["image", "style", "character", "modify_image"])
    func referenceModes(_ mode: String) async throws {
        let capture = Capture()
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST" { await capture.store(request) }
            if request.url!.host == "cdn.example.com" {
                return FetchResponse(body: .data(Data([1])), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
            }
            let json = request.httpMethod == "POST" ? #"{"id":"generation","state":"queued"}"# : #"{"id":"generation","state":"completed","assets":{"image":"https://cdn.example.com/image.png"}}"#
            return FetchResponse(body: .data(Data(json.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createLuma(settings: .init(apiKey: "token", fetch: fetch)).image(modelId: .photon1)
        let result = try await model.doGenerate(options: .init(prompt: "Edit", n: 1, aspectRatio: "16:9",
            files: [.url(url: "https://example.com/source.png", providerOptions: nil)],
            providerOptions: ["luma": ["referenceType": .string(mode), "images": .array([.object(["weight": .number(0.6), "id": .string("identity1")])]), "pollIntervalMillis": .number(1), "maxPollAttempts": .number(1), "custom": .bool(true)]]
        ))
        let request = try #require(await capture.value())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        let reference: JSONValue = .object(["url": .string("https://example.com/source.png"), "weight": .number(0.6)])
        let editing: JSONValue = mode == "character" ? .object(["identity1": .object(["images": .array([.string("https://example.com/source.png")])])]) : mode == "modify_image" ? reference : .array([reference])
        #expect(body == .object(["prompt": .string("Edit"), "model": .string("photon-1"), "aspect_ratio": .string("16:9"), mode: editing, "custom": .bool(true)]))
        #expect(result.images == .binary([Data([1])]))
    }

    @Test("default image references use model-specific weights")
    func defaultWeight() async throws {
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST" {
                let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
                guard case .object(let values) = body else { throw CancellationError() }
                #expect(values["image"] == .array([.object(["url": .string("https://example.com/source.png"), "weight": .number(0.85)])]))
            }
            let data = request.url!.host == "cdn.example.com" ? Data([1]) : Data(#"{"id":"generation","state":"completed","assets":{"image":"https://cdn.example.com/image.png"}}"#.utf8)
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createLuma(settings: .init(apiKey: "token", fetch: fetch)).image(modelId: .photon1)
        let result = try await model.doGenerate(options: .init(n: 1, files: [.url(url: "https://example.com/source.png", providerOptions: nil)]))
        #expect(result.images == .binary([Data([1])]))
    }

    @Test("unsupported binary images, masks and excess references fail before networking", arguments: ["binary", "mask", "excess", "modify", "character"])
    func rejectsInputs(_ scenario: String) async throws {
        let fetch: FetchFunction = { _ in
            Issue.record("Invalid editing input reached the network")
            throw CancellationError()
        }
        let model = createLuma(settings: .init(apiKey: "token", fetch: fetch)).image(modelId: .photon1)
        let image = ImageModelV4File.url(url: "https://example.com/source.png", providerOptions: nil)
        let files: [ImageModelV4File] = scenario == "binary" ? [.file(mediaType: "image/png", data: .binary(Data([1])), providerOptions: nil)] : Array(repeating: image, count: scenario == "modify" ? 2 : scenario == "excess" || scenario == "character" ? 5 : 1)
        let options = ImageModelV4CallOptions(n: 1, files: files, mask: scenario == "mask" ? image : nil, providerOptions: ["luma": ["referenceType": .string(scenario == "modify" ? "modify_image" : scenario == "character" ? "character" : "image")]])
        do {
            _ = try await model.doGenerate(options: options)
            Issue.record("Expected unsupported editing input to fail")
        } catch {
            #expect(error.localizedDescription.contains("Luma AI"))
        }
    }

    @Test("API error context is nullable but requires expected when present", arguments: [JSONValue.null, .object(["expected": .string("string")]), .object([:]), .object(["expected": .null])])
    func errorContext(_ context: JSONValue) async throws {
        let body = JSONValue.object(["detail": .array([.object(["type": .string("string_type"), "loc": .array([.string("prompt")]), "msg": .string("Invalid prompt"), "input": .string(""), "ctx": context])])])
        let data = try JSONEncoder().encode(body)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createLuma(settings: .init(apiKey: "token", fetch: fetch)).image(modelId: .photon1)
        do {
            _ = try await model.doGenerate(options: .init(n: 1))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            let valid: Bool
            if context == .null { valid = true }
            else if case .object(let object) = context, case .string = object["expected"] { valid = true }
            else { valid = false }
            #expect(error.statusCode == 400)
            #expect(error.message == (valid ? "Invalid prompt" : HTTPURLResponse.localizedString(forStatusCode: 400).capitalized))
        }
    }

    @Test("invalid image weights fail provider option validation")
    func rejectsWeight() async throws {
        let model = createLuma(settings: .init(apiKey: "token")).image(modelId: .photon1)
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(n: 1, providerOptions: ["luma": ["images": .array([.object(["weight": .number(2)])])]]))
        }
    }
}
