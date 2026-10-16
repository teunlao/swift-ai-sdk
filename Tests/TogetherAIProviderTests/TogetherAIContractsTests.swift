import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import TogetherAIProvider

@Suite("TogetherAI native contracts")
struct TogetherAIContractsTests {
    @Test func nonDiffusionImagesOmitDiffusionControlsAndReportUnsupportedSeed() async throws {
        let fetch: FetchFunction = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == ["model": "google/gemini-3-pro-image", "prompt": "Image", "response_format": "base64", "vendor_mode": "kept"])
            return FetchResponse(body: .data(Data(#"{"data":[{"b64_json":"result"}]}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = try createTogetherAI(settings: .init(apiKey: "key", fetch: fetch)).imageModel(modelId: "google/gemini-3-pro-image")
        #expect(try await model.supportsFileInputs == false)
        #expect(try await model.supportsMaskInputs == false)
        let result = try await model.doGenerate(options: .init(prompt: "Image", n: 1, seed: 1, providerOptions: ["togetherai": ["steps": 28, "guidance": 3.5, "negative_prompt": "blur", "disable_safety_checker": true, "vendor_mode": "kept"]]))
        #expect(result.images == .base64(["result"]))
        #expect(result.warnings.contains { if case .unsupported(feature: "seed", details: _) = $0 { return true }; return false })
    }
    @Test(arguments: [("black-forest-labs/FLUX.2-pro", true as Bool?), ("black-forest-labs/FLUX.2-dev", false as Bool?), ("future-image", nil as Bool?)])
    func capabilitiesDistinguishImageURLFromReferenceImages(modelId: String, expected: Bool?) async throws {
        let model = try createTogetherAI(settings: .init(apiKey: "key")).imageModel(modelId: modelId)
        #expect(try await model.supportsFileInputs == expected)
        #expect(try await model.supportsMaskInputs == (expected == nil ? nil : false))
    }
    @Test func rerankingRejectsNullRankFields() async throws {
        let optionalModel = try createTogetherAI(settings: .init(apiKey: "key", fetch: { _ in throw CancellationError() })).rerankingModel(modelId: "ranker")
        let model = try #require(optionalModel)
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doRerank(options: .init(documents: .text(values: ["value"]), query: "query", providerOptions: ["togetherai": ["rankFields": .null]]))
        }
    }
}
