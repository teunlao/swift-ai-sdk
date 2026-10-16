import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import ProdiaProvider

@Suite("Prodia V4 image input and pricing contracts")
struct ProdiaImageInputsTests {
    @Test("text-to-image excludes files and mask and returns billed dollars")
    func inputsAndPrice() async throws {
        let fetch: FetchFunction = { request in
            #expect(request.url?.absoluteString == "https://inference.prodia.com/v2/job?price=true")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object(["type": .string("inference.flux.schnell.txt2img.v2"), "config": .object(["prompt": .string("Draw"), "loras": .array([])])]))
            let multipart = "--boundary\r\nContent-Disposition: form-data; name=\"job\"\r\nContent-Type: application/json\r\n\r\n{\"id\":\"job\",\"price\":{\"product\":\"image\",\"dollars\":0.01}}\r\n--boundary\r\nContent-Disposition: form-data; name=\"output\"\r\nContent-Type: image/png\r\n\r\nimage\r\n--boundary--\r\n"
            return FetchResponse(body: .data(Data(multipart.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "multipart/form-data; boundary=boundary"])!)
        }
        let model = createProdia(settings: .init(apiKey: "secret", fetch: fetch)).image(.inferenceFluxSchnellTxt2imgV2)
        #expect(model.supportsFileInputs == false)
        #expect(model.supportsMaskInputs == false)
        let image = ImageModelV4File.url(url: "https://example.com/image.png", providerOptions: nil)
        let result = try await model.doGenerate(options: .init(prompt: "Draw", n: 1, aspectRatio: "16:9", files: [image], mask: image, providerOptions: ["prodia": ["loras": .array([]), "unsupported": .bool(true)]]))
        #expect(result.images == .binary([Data("image".utf8)]))
        #expect(result.providerMetadata?["prodia"]?.images == [.object(["jobId": .string("job"), "dollars": .number(0.01)])])
        #expect(result.warnings == [.unsupported(feature: "aspectRatio", details: "This provider does not support aspect ratio. Use `size` instead.")])
    }

    @Test("HTTP error fields distinguish optional strings from arbitrary detail", arguments: ["message-null", "error-null", "detail-null"])
    func errorFields(_ scenario: String) async throws {
        let json = scenario == "message-null" ? #"{"message":null}"# : scenario == "error-null" ? #"{"error":null}"# : #"{"detail":null,"message":"Provider message"}"#
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(Data(json.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createProdia(settings: .init(apiKey: "secret", fetch: fetch)).image(.inferenceFluxSchnellTxt2imgV2)
        do {
            _ = try await model.doGenerate(options: .init(n: 1))
            Issue.record("Expected HTTP error")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
            #expect(error.responseBody == json)
            #expect(error.message == (scenario == "detail-null" ? "Provider message" : HTTPURLResponse.localizedString(forStatusCode: 400).capitalized))
        }
    }

    @Test("invalid known provider options fail before request creation", arguments: [
        ["width": JSONValue.string("1024")], ["steps": .number(0)], ["progressive": .null], ["loras": .array([.string("a"), .string("b"), .string("c"), .string("d")])]
    ])
    func rejectsOptions(_ values: [String: JSONValue]) async throws {
        let model = createProdia(settings: .init(apiKey: "secret")).image(.inferenceFluxSchnellTxt2imgV2)
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(n: 1, providerOptions: ["prodia": values]))
        }
    }
}
