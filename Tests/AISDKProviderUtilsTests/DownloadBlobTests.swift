import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("downloadBlob")
struct DownloadBlobTests {
    @Test("downloads bytes and media type successfully")
    func downloadsBytesAndMediaType() async throws {
        let content = Data("test content".utf8)
        let fetch = FetchSequence([
            makeFetchResponse(
                url: "https://example.com/image.png",
                headers: ["Content-Type": "image/png"],
                body: content
            )
        ])

        let result = try await downloadBlob(
            url: "https://example.com/image.png",
            fetch: fetch.fetch
        )

        #expect(result == DownloadedBlob(data: content, mediaType: "image/png"))
        let request = try #require(await fetch.requests().first)
        #expect(request.url?.absoluteString == "https://example.com/image.png")
        #expect(request.allHTTPHeaderFields?.isEmpty != false)
    }

    @Test("throws DownloadError on non-ok response")
    func throwsDownloadErrorOnNonOkResponse() async throws {
        let fetch = FetchSequence([
            makeFetchResponse(
                url: "https://example.com/not-found.png",
                statusCode: 404,
                body: Data("missing".utf8)
            )
        ])

        do {
            _ = try await downloadBlob(
                url: "https://example.com/not-found.png",
                fetch: fetch.fetch
            )
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.url == "https://example.com/not-found.png")
            #expect(error.statusCode == 404)
            #expect(error.statusText == "Not Found")
            #expect(error.message == "Failed to download https://example.com/not-found.png: 404 Not Found")
        }
    }

    @Test("wraps network errors in DownloadError")
    func wrapsNetworkErrors() async throws {
        let fetch: FetchFunction = { _ in
            throw URLError(.cannotConnectToHost)
        }

        do {
            _ = try await downloadBlob(
                url: "https://example.com/network-error.png",
                fetch: fetch
            )
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.url == "https://example.com/network-error.png")
            #expect(error.cause is URLError)
            #expect(error.message.hasPrefix("Failed to download https://example.com/network-error.png:"))
        }
    }

    @Test("rethrows existing DownloadError without wrapping")
    func rethrowsDownloadErrorWithoutWrapping() async throws {
        let original = DownloadError(
            url: "https://example.com/original.png",
            statusCode: 500,
            statusText: "Internal Server Error"
        )

        let fetch: FetchFunction = { _ in
            throw original
        }

        do {
            _ = try await downloadBlob(
                url: "https://example.com/test.png",
                fetch: fetch
            )
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.url == original.url)
            #expect(error.statusCode == original.statusCode)
        }
    }

    @Test("rejects private URLs before fetch")
    func rejectsPrivateURLBeforeFetch() async throws {
        let fetch = FetchSequence([])

        do {
            _ = try await downloadBlob(
                url: "http://127.0.0.1/file",
                fetch: fetch.fetch
            )
            Issue.record("Expected DownloadError")
        } catch is DownloadError {
            #expect(await fetch.requests().isEmpty)
        }
    }

    @Test("rejects redirect to private URL before fetching target")
    func rejectsPrivateRedirectBeforeFetchingTarget() async throws {
        let fetch = FetchSequence([
            makeFetchResponse(
                url: "https://evil.com/redirect",
                statusCode: 302,
                headers: ["Location": "http://localhost:8080/admin"],
                body: Data("redirecting".utf8)
            )
        ])

        do {
            _ = try await downloadBlob(
                url: "https://evil.com/redirect",
                fetch: fetch.fetch
            )
            Issue.record("Expected DownloadError")
        } catch is DownloadError {
            let requests = await fetch.requests()
            #expect(requests.map { $0.url?.absoluteString } == [
                "https://evil.com/redirect"
            ])
        }
    }

    @Test("follows redirects to safe URLs")
    func followsSafeRedirects() async throws {
        let content = Data("safe content".utf8)
        let fetch = FetchSequence([
            makeFetchResponse(
                url: "https://example.com/image.png",
                statusCode: 302,
                headers: ["Location": "https://cdn.example.com/image.png"]
            ),
            makeFetchResponse(
                url: "https://cdn.example.com/image.png",
                headers: ["Content-Type": "image/png"],
                body: content
            ),
        ])

        let result = try await downloadBlob(
            url: "https://example.com/image.png",
            fetch: fetch.fetch
        )

        #expect(result == DownloadedBlob(data: content, mediaType: "image/png"))

        let requests = await fetch.requests()
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://example.com/image.png",
            "https://cdn.example.com/image.png",
        ])
    }

    @Test("decodes data URLs without network fetch")
    func decodesDataURLs() async throws {
        let result = try await downloadBlob(
            url: "data:text/plain;base64,aGVsbG8=",
            fetch: FetchSequence([]).fetch
        )

        #expect(result == DownloadedBlob(data: Data("hello".utf8), mediaType: "text/plain"))
    }

    @Test("rejects data URLs over maxBytes")
    func rejectsOversizedDataURLs() async throws {
        do {
            _ = try await downloadBlob(
                url: "data:text/plain;base64,aGVsbG8=",
                maxBytes: 3,
                fetch: FetchSequence([]).fetch
            )
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.message.contains("exceeded maximum size of 3 bytes"))
        }
    }
}
