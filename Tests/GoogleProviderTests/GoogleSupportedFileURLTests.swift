import Foundation
import Testing
@testable import GoogleProvider

/**
 Tests for isGoogleSupportedFileURL function.

 Port of `@ai-sdk/google/src/google-supported-file-url.test.ts`.
 */

@Suite("GoogleSupportedFileURL")
struct GoogleSupportedFileURLTests {
    @Test("should return true for valid Google generative language file URLs")
    func validGoogleFileURLs() throws {
        let validUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/files/00000000-00000000-00000000-00000000")!
        #expect(isGoogleSupportedFileURL(validUrl) == true)

        let simpleValidUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/files/test123")!
        #expect(isGoogleSupportedFileURL(simpleValidUrl) == true)
    }

    @Test("should return true for valid YouTube URLs")
    func validYouTubeURLs() throws {
        let validYouTubeUrls = [
            URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
            URL(string: "https://youtube.com/watch?v=dQw4w9WgXcQ")!,
            URL(string: "https://youtu.be/dQw4w9WgXcQ")!,
            URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=youtu.be")!,
            URL(string: "https://youtu.be/dQw4w9WgXcQ?t=42")!
        ]

        for url in validYouTubeUrls {
            #expect(isGoogleSupportedFileURL(url) == true)
        }
    }

    @Test("should return false for invalid YouTube URLs")
    func invalidYouTubeURLs() throws {
        let invalidYouTubeUrls = [
            URL(string: "https://youtube.com/channel/UCdQw4w9WgXcQ")!,
            URL(string: "https://youtube.com/playlist?list=PLdQw4w9WgXcQ")!,
            URL(string: "https://m.youtube.com/watch?v=dQw4w9WgXcQ")!,
            URL(string: "http://youtube.com/watch?v=dQw4w9WgXcQ")!,
            URL(string: "https://vimeo.com/123456789")!
        ]

        for url in invalidYouTubeUrls {
            #expect(isGoogleSupportedFileURL(url) == false)
        }
    }

    @Test("should return false for non-Google generative language file URLs")
    func nonGoogleFileURLs() throws {
        let testCases = [
            URL(string: "https://example.com")!,
            URL(string: "https://example.com/foo/bar")!,
            URL(string: "https://generativelanguage.googleapis.com")!,
            URL(string: "https://generativelanguage.googleapis.com/v1/other")!,
            URL(string: "http://generativelanguage.googleapis.com/v1beta/files/test")!,
            URL(string: "https://api.googleapis.com/v1beta/files/test")!
        ]

        for url in testCases {
            #expect(isGoogleSupportedFileURL(url) == false)
        }
    }
}
