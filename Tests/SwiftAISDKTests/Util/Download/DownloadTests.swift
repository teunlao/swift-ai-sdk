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
        let url = URL(string: "https://example.com/success")!
        let expectedBody = "<html>ok</html>".data(using: .utf8)!
        let contentType = "text/html; charset=utf-8"

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!

        let fetch = makeMockFetch(url: url, response: response, body: expectedBody)

        let result = try await download(url: url, fetch: fetch)

        // Verify we got data
        #expect(result.data == expectedBody)

        // Verify media type contains text/html
        #expect(result.mediaType == contentType)
    }

    @Test("download should throw DownloadError when response is not ok (404)")
        func testDownload404Error() async throws {
        let url = URL(string: "https://example.com/not-found")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch = makeMockFetch(url: url, response: response, body: Data())

        do {
            _ = try await download(url: url, fetch: fetch)
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
        let url = URL(string: "https://example.com/server-error")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch = makeMockFetch(url: url, response: response, body: Data())

        do {
            _ = try await download(url: url, fetch: fetch)
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
        let url = URL(string: "https://example.com/user-agent")!
        let expectedBody = Data("ok".utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let fetch = makeMockFetch(url: url, response: response, body: expectedBody) { request in
            #expect(request.url == url)
            let header = request.value(forHTTPHeaderField: "User-Agent")
            #expect(header?.contains("ai-sdk/") == true)
        }

        let result = try await download(url: url, fetch: fetch)
        #expect(result.data == expectedBody)
    }

    @Test("createDownload should download data URLs")
    func testCreateDownloadDataURL() async throws {
        let url = URL(string: "data:text/plain;base64,b2s=")!
        let download = createDownload()

        let result = try await download(DownloadFileRequest(url: url))

        #expect(result.data == Data("ok".utf8))
        #expect(result.mediaType == "text/plain")
    }

    @Test("createDownload should enforce maxBytes")
    func testCreateDownloadMaxBytes() async throws {
        let url = URL(string: "data:text/plain;base64,b2s=")!
        let download = createDownload(maxBytes: 1)

        do {
            _ = try await download(DownloadFileRequest(url: url))
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.url == url.absoluteString)
            #expect(error.message.contains("exceeded maximum size of 1 bytes"))
        }
    }

    // MARK: - Helpers

    private func makeMockFetch(
        url: URL,
        response: HTTPURLResponse,
        body: Data,
        inspectRequest: (@Sendable (URLRequest) -> Void)? = nil
    ) -> FetchFunction {
        { request in
            #expect(request.url == url)
            inspectRequest?(request)
            return FetchResponse(body: .data(body), urlResponse: response)
        }
    }
}
