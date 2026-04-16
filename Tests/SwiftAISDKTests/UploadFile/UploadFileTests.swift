import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

private actor UploadFileOptionsCapture {
    private var options: [FilesV4UploadFileCallOptions] = []

    func append(_ value: FilesV4UploadFileCallOptions) {
        options.append(value)
    }

    func first() -> FilesV4UploadFileCallOptions? {
        options.first
    }
}

private final class MockFilesAPI: FilesV4 {
    let specificationVersion = "v4"
    let provider = "mock.files"

    private let capture: UploadFileOptionsCapture
    private let result: FilesV4UploadFileResult

    init(capture: UploadFileOptionsCapture, result: FilesV4UploadFileResult) {
        self.capture = capture
        self.result = result
    }

    func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        await capture.append(options)
        return result
    }
}

private final class MockFilesProvider: ProviderV3, FilesProvider {
    private let filesAPI: any FilesV4

    init(filesAPI: any FilesV4) {
        self.filesAPI = filesAPI
    }

    func files() -> any FilesV4 {
        filesAPI
    }

    func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

private final class UnsupportedUploadProvider: ProviderV3 {
    func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

@Suite("uploadFile")
struct UploadFileTests {
    @Test("detects PDF media type when not provided")
    func detectsPDFMediaType() async throws {
        let capture = UploadFileOptionsCapture()
        let api = MockFilesAPI(
            capture: capture,
            result: .init(providerReference: ["anthropic": "file-1"])
        )

        _ = try await uploadFile(
            api: api,
            data: DataContentOrURL.data(Data([0x25, 0x50, 0x44, 0x46]))
        )

        #expect(await capture.first()?.mediaType == "application/pdf")
    }

    @Test("falls back to text/plain for utf8 data")
    func fallsBackToTextPlain() async throws {
        let capture = UploadFileOptionsCapture()
        let api = MockFilesAPI(
            capture: capture,
            result: .init(providerReference: ["anthropic": "file-1"])
        )

        _ = try await uploadFile(
            api: api,
            data: DataContentOrURL.data(Data("hello world".utf8))
        )

        #expect(await capture.first()?.mediaType == "text/plain")
    }

    @Test("detects media type for base64url image input")
    func detectsMediaTypeForBase64URLImageInput() async throws {
        let capture = UploadFileOptionsCapture()
        let api = MockFilesAPI(
            capture: capture,
            result: .init(providerReference: ["anthropic": "file-1"])
        )

        let jpegBase64URL = Data([0xFF, 0xD8, 0xFF, 0xE0]).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        _ = try await uploadFile(
            api: api,
            data: DataContentOrURL.string(jpegBase64URL)
        )

        #expect(await capture.first()?.mediaType == "image/jpeg")
    }

    @Test("provider overload routes through files capability")
    func providerOverloadUsesFilesCapability() async throws {
        let capture = UploadFileOptionsCapture()
        let api = MockFilesAPI(
            capture: capture,
            result: .init(
                providerReference: ["anthropic": "file-123"],
                mediaType: "application/pdf",
                filename: "guide.pdf"
            )
        )
        let provider = MockFilesProvider(filesAPI: api)

        let result = try await uploadFile(
            api: provider,
            data: DataContentOrURL.data(Data([0x25, 0x50, 0x44, 0x46]))
        )

        #expect(result.providerReference["anthropic"] == "file-123")
        #expect(result.mediaType == "application/pdf")
        #expect(await capture.first()?.mediaType == "application/pdf")
    }

    @Test("rejects URL data and unsupported providers with upstream-style messages")
    func rejectsUnsupportedInputs() async throws {
        let capture = UploadFileOptionsCapture()
        let api = MockFilesAPI(
            capture: capture,
            result: .init(providerReference: ["anthropic": "file-1"])
        )

        do {
            _ = try await uploadFile(
                api: api,
                data: DataContentOrURL.url(URL(string: "https://example.com/file.pdf")!)
            )
            Issue.record("Expected URL upload to throw")
        } catch let error as InvalidArgumentError {
            #expect(error.message == "URL data is not supported for file uploads. Fetch the URL content first and pass the bytes.")
        }

        do {
            _ = try await uploadFile(
                api: UnsupportedUploadProvider(),
                data: DataContentOrURL.data(Data([0x01, 0x02]))
            )
            Issue.record("Expected unsupported provider to throw")
        } catch let error as InvalidArgumentError {
            #expect(error.message == "The provider does not support file uploads. Make sure it exposes a files() method.")
        }
    }
}
