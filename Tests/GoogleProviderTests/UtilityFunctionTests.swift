import Foundation
import Testing
@testable import GoogleProvider

@Suite("Google utility functions")
struct GoogleUtilityFunctionTests {
    @Test("getGoogleModelPath prepends models prefix when missing")
    func modelPath() throws {
        #expect(getGoogleModelPath("gemini-pro") == "models/gemini-pro")
        #expect(getGoogleModelPath("models/gemini-pro") == "models/gemini-pro")
    }

    @Test("isGoogleSupportedFileURL recognizes google files and youtube")
    func supportedFileURLs() throws {
        #expect(isGoogleSupportedFileURL(URL(string: "https://generativelanguage.googleapis.com/v1beta/files/abc")!))
        #expect(isGoogleSupportedFileURL(URL(string: "https://www.youtube.com/watch?v=abcd")!))
        #expect(isGoogleSupportedFileURL(URL(string: "https://youtu.be/abcd")!))
        #expect(isGoogleSupportedFileURL(URL(string: "https://example.com/video")!) == false)
    }
}
