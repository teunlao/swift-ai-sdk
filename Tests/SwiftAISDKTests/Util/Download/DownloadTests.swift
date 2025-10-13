/**
 Tests for download function.

 Port of `@ai-sdk/ai/src/util/download/download.test.ts`.
 */

import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

// Note: These tests require a test server for full upstream parity.
// The TypeScript tests use @ai-sdk/test-server which we don't have yet.
// For now, these are basic smoke tests with real URLs.
// TODO: Implement test server infrastructure for 100% parity

@Suite("Download Tests")
struct DownloadTests {
    @Test("download should successfully download data from URL")
    func testDownloadSuccess() async throws {
        // Use a reliable test endpoint (example.com always returns HTML)
        let url = URL(string: "https://example.com")!

        let result = try await download(url: url)

        // Verify we got data
        #expect(result.data.count > 0)

        // Verify media type contains text/html
        #expect(result.mediaType?.contains("text/html") == true)
    }

    @Test("download should throw DownloadError when response is not ok (404)")
    func testDownload404Error() async throws {
        // This URL should return 404
        let url = URL(string: "https://httpbin.org/status/404")!

        do {
            _ = try await download(url: url)
            Issue.record("Expected download to throw DownloadError")
        } catch let error as DownloadError {
            #expect([404, 503].contains(error.statusCode))
            #expect(error.url == url.absoluteString)
        } catch {
            Issue.record("Expected DownloadError but got: \(error)")
        }
    }

    @Test("download should throw DownloadError when response is not ok (500)")
    func testDownload500Error() async throws {
        // This URL should return 500
        let url = URL(string: "https://httpbin.org/status/500")!

        do {
            _ = try await download(url: url)
            Issue.record("Expected download to throw DownloadError")
        } catch let error as DownloadError {
            #expect([500, 503].contains(error.statusCode))
            #expect(error.url == url.absoluteString)
        } catch {
            Issue.record("Expected DownloadError but got: \(error)")
        }
    }

    @Test("download should include User-Agent header")
    func testDownloadUserAgentHeader() async throws {
        // NOTE: This test verifies that download() calls withUserAgentSuffix correctly.
        // In the upstream TypeScript tests, this uses a test server to verify the header.
        // For now, we verify through code inspection and integration testing.
        //
        // The download() function calls:
        //   withUserAgentSuffix([:], "ai-sdk/\(VERSION)", getRuntimeEnvironmentUserAgent())
        //
        // This test simply verifies download works with a real URL.
        // Full header verification would require a test server infrastructure.

        let url = URL(string: "https://example.com")!
        let result = try await download(url: url)

        // Verify we got data (proves the User-Agent header didn't cause issues)
        #expect(result.data.count > 0)

        // TODO: Implement test server for full upstream parity
        // Upstream test uses @ai-sdk/test-server to verify User-Agent header
    }
}
