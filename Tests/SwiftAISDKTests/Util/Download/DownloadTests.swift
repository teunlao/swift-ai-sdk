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

        private func registerMock(
        for url: URL,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
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

@preconcurrency private final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private final class HandlerStore: @unchecked Sendable {
        private let queue = DispatchQueue(label: "mock-url-protocol.handlers", attributes: .concurrent)
        private var handlers: [String: Handler] = [:]

        @discardableResult
        private func barrier<T>(_ block: () -> T) -> T {
            queue.sync(flags: .barrier, execute: block)
        }

        func install(_ handler: @escaping Handler, for url: String) {
            barrier { handlers[url] = handler }
        }

        func remove(for url: String) {
            barrier { handlers.removeValue(forKey: url) }
        }

        func handler(for url: String) -> Handler? {
            queue.sync { handlers[url] }
        }
    }

    private static let handlerStore = HandlerStore()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        return handlerStore.handler(for: url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url?.absoluteString else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let handler = MockURLProtocol.handlerStore.handler(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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

    static func install(handler: @escaping Handler, for url: URL) {
        handlerStore.install(handler, for: url.absoluteString)
    }

    static func removeHandler(for url: URL) {
        handlerStore.remove(for: url.absoluteString)
    }

    private static func currentHandler(for url: String) -> Handler? {
        handlerStore.handler(for: url)
    }
}
