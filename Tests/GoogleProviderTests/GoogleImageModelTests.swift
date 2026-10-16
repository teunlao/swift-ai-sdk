import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google image V4")
struct GoogleImageModelTests {
    @Test("Gemini image generation forwards file inputs and search grounding")
    func imageGeneration() async throws {
        let transport = GoogleTransport([.init(try googleFixture("image.json"))])
        let model = await transport.provider().image(modelId: "gemini-nano-banana-2.1")
        let result = try await model.doGenerate(options: .init(prompt: "otter", n: 1, aspectRatio: "8:1", files: [.file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil)], providerOptions: ["google": ["googleSearch": .object(["searchTypes": .object(["imageSearch": .object([:])])]), "imageConfig": .object(["imageSize": .string("512")])]]))
        #expect(result.images == .base64(["AQID"]))
        #expect(result.usage?.totalTokens == 8)
        #expect(try await model.supportsFileInputs == true)
        #expect(try await model.supportsMaskInputs == false)
        #expect(object(result.providerMetadata?["google"]?.additionalData)["finishReason"] == .string("STOP"))
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        #expect(object(body["generationConfig"])["responseModalities"] == .array([.string("IMAGE")]))
        #expect(object(object(body["generationConfig"])["imageConfig"])["aspectRatio"] == .string("8:1"))
        #expect(object(array(body["tools"]).first)["googleSearch"] == .object(["searchTypes": .object(["imageSearch": .object([:])])]))
    }

    @Test("blocked image generation is marked nonretryable")
    func blockedImage() async throws {
        let transport = GoogleTransport([.init(try googleFixture("blocked.json"))])
        let model = await transport.provider().image(modelId: "gemini-2.5-flash-image")
        let result = try await model.doGenerate(options: .init(prompt: "blocked", n: 1))
        #expect(result.images == .base64([]))
        #expect(result.isRetryable == false)
    }

    @Test("image requests reject masks and non-Gemini models")
    func unsupportedImageCalls() async throws {
        let provider = createGoogle(settings: .init(apiKey: "key"))
        let mask = ImageModelV4File.file(mediaType: "image/png", data: .base64("AQID"), providerOptions: nil)
        await #expect(throws: InvalidArgumentError.self) { try await provider.image(modelId: "gemini-2.5-flash-image").doGenerate(options: .init(prompt: "edit", n: 1, mask: mask)) }
        await #expect(throws: UnsupportedFunctionalityError.self) { try await provider.image(modelId: "imagen-4.0-generate-001").doGenerate(options: .init(prompt: "image", n: 1)) }
    }
}
