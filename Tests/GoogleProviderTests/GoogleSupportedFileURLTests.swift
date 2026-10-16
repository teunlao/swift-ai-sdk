import Foundation
import Testing
import AISDKProviderUtils
import GoogleProvider

@Suite("Google native file URL capabilities")
struct GoogleSupportedFileURLTests {
    @Test("newer Gemini supports external media by subtype and older models retain file URLs")
    func supportedURLs() async throws {
        let provider = createGoogle(settings: .init(baseURL: "https://proxy.example/v1beta"))
        let modern = try await provider.chat(modelId: "gemini-3.8-flash").supportedUrls
        let legacy = try await provider.chat(modelId: "gemini-2.0-flash").supportedUrls
        #expect(isUrlSupported(mediaType: "image/png", url: "https://example.com/image.png", supportedUrls: modern))
        #expect(!isUrlSupported(mediaType: "audio/mp3", url: "https://example.com/audio.mp3", supportedUrls: modern))
        #expect(!isUrlSupported(mediaType: "image/png", url: "https://example.com/image.png", supportedUrls: legacy))
        #expect(isUrlSupported(mediaType: "image/png", url: "https://generativelanguage.googleapis.com/v1beta/files/id", supportedUrls: legacy))
        #expect(isUrlSupported(mediaType: "video/mp4", url: "https://youtu.be/abc", supportedUrls: legacy))
    }
}
