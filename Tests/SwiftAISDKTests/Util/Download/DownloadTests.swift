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
    @MainActor
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

        let teardown = try registerMock(for: url) { request in
            #expect(request.url == url)
            return (response, expectedBody)
        }
        defer { teardown() }

        let result = try await download(url: url)

        // Verify we got data
        #expect(result.data == expectedBody)

        // Verify media type contains text/html
        #expect(result.mediaType == contentType)
    }

    @Test("download should throw DownloadError when response is not ok (404)")
    @MainActor
    func testDownload404Error() async throws {
        let url = URL(string: "https://example.com/not-found")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!

        let teardown = try registerMock(for: url) { request in
            #expect(request.url == url)
            return (response, Data())
        }
        defer { teardown() }

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
    @MainActor
    func testDownload500Error() async throws {
        let url = URL(string: "https://example.com/server-error")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!

        let teardown = try registerMock(for: url) { request in
            #expect(request.url == url)
            return (response, Data())
        }
        defer { teardown() }

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
    @MainActor
    func testDownloadUserAgentHeader() async throws {
        let url = URL(string: "https://example.com/user-agent")!
        let expectedBody = Data("ok".utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let teardown = try registerMock(for: url) { request in
            #expect(request.url == url)
            let header = request.value(forHTTPHeaderField: "User-Agent")
            #expect(header?.contains("ai-sdk/") == true)
            return (response, expectedBody)
        }
        defer { teardown() }

        let result = try await download(url: url)
        #expect(result.data == expectedBody)
    }

    // MARK: - Helpers

    @MainActor
    private func registerMock(
        for url: URL,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> () -> Void {
        MockURLProtocol.install(handler: handler, for: url)
        guard URLProtocol.registerClass(MockURLProtocol.self) else {
            throw DownloadTestError.registrationFailed
        }
        return {
            URLProtocol.unregisterClass(MockURLProtocol.self)
            MockURLProtocol.removeHandler(for: url)
        }
    }

    private enum DownloadTestError: Error {
        case registrationFailed
    }
}

@MainActor
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static let handlerLock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        return currentHandler(for: url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url?.absoluteString,
            let handler = MockURLProtocol.currentHandler(for: url)
        else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.unknown)
            )
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Nothing to do
    }

    @MainActor
    static func install(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data), for url: URL) {
        handlerLock.lock()
        handlers[url.absoluteString] = handler
        handlerLock.unlock()
    }

    @MainActor
    static func removeHandler(for url: URL) {
        handlerLock.lock()
        handlers.removeValue(forKey: url.absoluteString)
        handlerLock.unlock()
    }

    nonisolated(unsafe) private static func currentHandler(for url: String) -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        handlerLock.lock()
        defer { handlerLock.unlock() }
        return handlers[url]
    }
}
