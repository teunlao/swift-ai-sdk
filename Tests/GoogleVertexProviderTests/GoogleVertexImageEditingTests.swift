import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexImageModel (editing)")
struct GoogleVertexImageEditingTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?

        func set(_ request: URLRequest) {
            lastRequest = request
        }
    }

    private func makeOKResponse(url: URL) throws -> FetchResponse {
        let json = #"{"predictions":[{"bytesBase64Encoded":"AQID","mimeType":"image/png","prompt":"revised"}]}"#
        let data = Data(json.utf8)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    @Test("should build edit-mode request with referenceImages and edit parameters")
    func buildsEditModeRequest() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makeOKResponse(url: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch
        ))

        let model = try provider.imageModel(modelId: "imagen-3.0-generate-001")

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "edit me",
            n: 1,
            providerOptions: [
                "vertex": [
                    "negativePrompt": .string("no"),
                    "sampleImageSize": .string("2K"),
                    "edit": .object([
                        "baseSteps": .number(35),
                        "mode": .string("EDIT_MODE_OUTPAINT"),
                        "maskMode": .string("MASK_MODE_DETECTION_BOX"),
                        "maskDilation": .number(0.01)
                    ])
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .base64("AAAA"), providerOptions: nil)
            ],
            mask: .file(mediaType: "image/png", data: .base64("BBBB"), providerOptions: nil)
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let jsonObject = try JSONSerialization.jsonObject(with: body)
        let root = try #require(jsonObject as? [String: Any])

        let instances = try #require(root["instances"] as? [[String: Any]])
        let instance = try #require(instances.first)
        #expect(instance["prompt"] as? String == "edit me")

        let referenceImages = try #require(instance["referenceImages"] as? [[String: Any]])
        #expect(referenceImages.count == 2)

        let rawRef = try #require(referenceImages.first)
        #expect(rawRef["referenceType"] as? String == "REFERENCE_TYPE_RAW")
        #expect((rawRef["referenceId"] as? Double).map(Int.init) == 1)

        let maskRef = try #require(referenceImages.last)
        #expect(maskRef["referenceType"] as? String == "REFERENCE_TYPE_MASK")
        #expect((maskRef["referenceId"] as? Double).map(Int.init) == 2)

        let maskConfig = try #require(maskRef["maskImageConfig"] as? [String: Any])
        #expect(maskConfig["maskMode"] as? String == "MASK_MODE_DETECTION_BOX")
        #expect(maskConfig["dilation"] as? Double == 0.01)

        let parameters = try #require(root["parameters"] as? [String: Any])
        #expect(parameters["sampleCount"] as? Double == 1)
        #expect(parameters["negativePrompt"] as? String == "no")
        #expect(parameters["sampleImageSize"] as? String == "2K")
        #expect(parameters["editMode"] as? String == "EDIT_MODE_OUTPAINT")

        let editConfig = try #require(parameters["editConfig"] as? [String: Any])
        #expect(editConfig["baseSteps"] as? Double == 35)
    }

    @Test("should omit prompt in request when prompt is nil")
    func omitsPromptWhenNil() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makeOKResponse(url: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch
        ))

        let model = try provider.imageModel(modelId: "imagen-3.0-generate-001")

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: nil,
            n: 1,
            files: [.file(mediaType: "image/png", data: .base64("AAAA"), providerOptions: nil)]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let jsonObject = try JSONSerialization.jsonObject(with: body)
        let root = try #require(jsonObject as? [String: Any])
        let instances = try #require(root["instances"] as? [[String: Any]])
        let instance = try #require(instances.first)
        #expect(instance["prompt"] == nil)
    }

    @Test("should reject URL-based images for edit mode")
    func rejectsURLBasedImagesForEditing() async throws {
        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project"
        ))

        let model = try provider.imageModel(modelId: "imagen-3.0-generate-001")

        do {
            _ = try await model.doGenerate(options: ImageModelV3CallOptions(
                prompt: "edit me",
                n: 1,
                files: [
                    .url(url: "https://example.com/image.png", providerOptions: nil)
                ]
            ))
            Issue.record("Expected error for URL-based edit input")
        } catch {
            #expect(error.localizedDescription == "URL-based images are not supported for Google Vertex image editing. Please provide the image data directly.")
        }
    }
}

