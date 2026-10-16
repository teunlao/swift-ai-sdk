import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google files V4")
struct GoogleFilesTests {
    @Test("resumable uploads separate authentication and poll encoded file resources")
    func resumableUpload() async throws {
        let transport = GoogleTransport([.init(Data(), headers: ["x-goog-upload-url": "https://uploads.example/session"]), .init(try googleFixture("file-upload.json")), .init(try googleFixture("file-active.json"))])
        let provider = await transport.provider()
        let interface = try provider.files()
        let files = try #require(interface)
        let result = try await files.uploadFile(options: .init(data: .data(Data([1, 2, 3])), mediaType: "application/pdf", filename: "source.pdf", providerOptions: ["google": ["displayName": .string("document"), "pollIntervalMs": .number(1)]]))
        #expect(result.providerReference == ["google": "https://generativelanguage.googleapis.com/v1beta/files/id"])
        #expect(result.providerMetadata?["google"]?["sha256Hash"] == .string("digest"))
        #expect(result.warnings == [.unsupported(feature: "filename", details: nil)])
        let requests = await transport.captured()
        #expect(requests[0].url?.absoluteString == "https://provider.example/upload/v1beta/files")
        #expect(object(try googleBody(requests[0])["file"])["display_name"] == .string("document"))
        #expect(requests[0].value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length") == "3")
        #expect(requests[1].httpBody == Data([1, 2, 3]))
        #expect(requests[1].value(forHTTPHeaderField: "x-goog-api-key") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "X-Goog-Upload-Command") == "upload, finalize")
        #expect(requests[2].url?.absoluteString == "https://provider.example/v1beta/files/%252E%252E")
    }
}
