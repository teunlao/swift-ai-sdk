import Foundation
import Testing
import AISDKProvider
import AmazonBedrockProvider

@Suite("Bedrock image V4 contracts")
struct BedrockImageModelTests {
    @Test("Nova Canvas advertises editing capabilities and sends validated generation options")
    func textImage() async throws {
        let server = try BedrockTestServer(json: .object(["images": .array([.string("image-a"), .string("image-b")])]), headers: ["x-request-id": "id"])
        let model = server.provider().image(modelId: .amazonNovaCanvasV1)
        let before = Date()
        let result = try await model.doGenerate(options: .init(prompt: "otter", n: 2, size: "512x1024", aspectRatio: "1:1", seed: 42, providerOptions: ["amazonBedrock": ["quality": .string("premium"), "cfgScale": .number(7), "negativeText": .string("blur"), "style": .string("PHOTOREALISM")]]))
        #expect(model.supportsFileInputs == true)
        #expect(model.supportsMaskInputs == true)
        #expect(result.images == .base64(["image-a", "image-b"]))
        #expect(result.response.timestamp >= before && result.response.timestamp <= Date())
        #expect(result.response.headers?["x-request-id"] == "id")
        #expect(result.warnings.count == 1)
        #expect(try await server.requestBody() == .object([
            "taskType": .string("TEXT_IMAGE"), "textToImageParams": .object(["text": .string("otter"), "negativeText": .string("blur"), "style": .string("PHOTOREALISM")]),
            "imageGenerationConfig": .object(["numberOfImages": .number(2), "width": .number(512), "height": .number(1024), "seed": .number(42), "quality": .string("premium"), "cfgScale": .number(7)])
        ]))
    }

    @Test("Image editing modes use the correct Bedrock params", arguments: ["INPAINTING", "OUTPAINTING", "IMAGE_VARIATION", "BACKGROUND_REMOVAL"])
    func editModes(_ task: String) async throws {
        let server = try BedrockTestServer(json: .object(["images": .array([.string("edited")])]))
        let result = try await server.provider().image(modelId: .amazonNovaCanvasV1).doGenerate(options: .init(prompt: "edit", n: 1, files: [.file(mediaType: "image/png", data: .binary(Data([1, 2])), providerOptions: nil), .file(mediaType: "image/png", data: .base64("AQI="), providerOptions: nil)], mask: .file(mediaType: "image/png", data: .base64("mask"), providerOptions: nil), providerOptions: ["amazonBedrock": ["taskType": .string(task), "maskPrompt": .string("sky"), "outPaintingMode": .string("PRECISE"), "similarityStrength": .number(0)]]))
        #expect(result.images == .base64(["edited"]))
        let body = try await server.requestBody()
        #expect(body["taskType"] == .string(task))
        switch task {
        case "INPAINTING": #expect(body["inPaintingParams"] == .object(["image": .string("AQI="), "maskImage": .string("mask"), "text": .string("edit")]))
        case "OUTPAINTING": #expect(body["outPaintingParams"] == .object(["image": .string("AQI="), "maskImage": .string("mask"), "text": .string("edit"), "outPaintingMode": .string("PRECISE")]))
        case "IMAGE_VARIATION": #expect(body["imageVariationParams"] == .object(["images": .array([.string("AQI="), .string("AQI=")]), "text": .string("edit"), "similarityStrength": .number(0)]))
        default:
            #expect(body["backgroundRemovalParams"] == .object(["image": .string("AQI=")]))
            #expect(body["imageGenerationConfig"] == nil)
        }
    }

    @Test("Image editing infers inpainting from maskPrompt")
    func inferredInpainting() async throws {
        let server = try BedrockTestServer(json: .object(["images": .array([.string("edited")])]))
        _ = try await server.provider().image(modelId: .amazonNovaCanvasV1).doGenerate(options: .init(prompt: nil, n: 1, files: [.file(mediaType: "image/png", data: .base64("image"), providerOptions: nil)], providerOptions: ["bedrock": ["maskPrompt": .string("sky")]]))
        #expect(try await server.requestBody()["inPaintingParams"] == .object(["image": .string("image"), "maskPrompt": .string("sky")]))
    }

    @Test("Moderation and empty image responses fail", arguments: [false, true])
    func rejectedImages(_ moderated: Bool) async throws {
        let body: JSONValue = moderated ? .object(["status": .string("Request Moderated"), "details": .object(["Moderation Reasons": .array([.string("blocked")])])]) : .object(["images": .array([])])
        let model = try BedrockTestServer(json: body).provider().image(modelId: .amazonNovaCanvasV1)
        do { _ = try await model.doGenerate(options: .init(prompt: "image", n: 1)); Issue.record("Expected image failure") }
        catch { #expect(error.localizedDescription.contains(moderated ? "moderated: blocked" : "returned no images")) }
    }

    @Test("Invalid options and URL editing fail before transport")
    func invalidInput() async throws {
        let model = try BedrockTestServer().provider().image(modelId: .amazonNovaCanvasV1)
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: "image", n: 1, providerOptions: ["amazonBedrock": ["quality": .string("invalid")]]))
        }
        do {
            _ = try await model.doGenerate(options: .init(prompt: "image", n: 1, files: [.url(url: "https://example.com/image.png", providerOptions: nil)]))
            Issue.record("Expected URL editing failure")
        } catch { #expect(error.localizedDescription.contains("URL-based images")) }
    }
}
