import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex image editing V4")
struct GoogleVertexImageEditingTests {
    @Test func inputFilesPreserveOpaqueGCSNames() async throws {
        let requests = VertexRequests()
        let model = try vertexProvider { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}}]},"finishReason":"STOP"}]}"#)
        }.imageModel(modelId: "gemini-2.5-flash-image")
        #expect(try await model.supportsFileInputs == true)
        #expect(try await model.supportsMaskInputs == false)
        let uri = "gs://bucket/image%2Fpart%25.png"
        let result = try await model.doGenerate(options: .init(prompt: "edit", n: 1, files: [
            .file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil),
            .url(url: uri, providerOptions: nil)
        ]))
        #expect(result.images == .base64(["AQID"]))
        let request = try #require(await requests.last)
        guard case .object(let body) = try vertexBody(request), case .array(let contents) = body["contents"],
              case .object(let user) = contents.first, case .array(let parts) = user["parts"] else {
            Issue.record("Missing user contents"); return
        }
        #expect(parts[1] == .object(["inlineData": .object(["mimeType": .string("image/png"), "data": .string("AQID")])]))
        guard case .object(let file) = parts[2], case .object(let data) = file["fileData"] else { Issue.record("Missing GCS part"); return }
        #expect(data["fileUri"] == .string(uri))
    }

    @Test func rejectsMaskAndRelativeFile() async throws {
        let model = try vertexProvider { _ in throw CancellationError() }.imageModel(modelId: "gemini-2.5-flash-image")
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(n: 1, mask: .file(mediaType: "image/png", data: .base64("AQID"), providerOptions: nil)))
        }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(n: 1, files: [.url(url: "image.png", providerOptions: nil)]))
        }
    }
}
