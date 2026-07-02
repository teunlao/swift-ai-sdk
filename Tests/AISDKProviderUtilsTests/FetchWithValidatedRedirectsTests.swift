import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("fetchWithValidatedRedirects")
struct FetchWithValidatedRedirectsTests {
    @Test("validates initial URL before requesting it")
    func validatesInitialURLBeforeRequesting() async throws {
        let fetch = FetchSequence([])

        do {
            _ = try await fetchWithValidatedRedirects(
                url: "http://localhost/file",
                fetch: fetch.fetch
            )
            Issue.record("Expected DownloadError")
        } catch is DownloadError {
            let requests = await fetch.requests()
            #expect(requests.isEmpty)
        }
    }

    @Test("uses bare GET request when headers are omitted")
    func usesBareRequestWhenHeadersOmitted() async throws {
        let fetch = FetchSequence([
            makeFetchResponse(url: "https://example.com/file", body: Data("ok".utf8))
        ])

        _ = try await fetchWithValidatedRedirects(
            url: "https://example.com/file",
            fetch: fetch.fetch
        )

        let request = try #require(await fetch.requests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://example.com/file")
        #expect(request.allHTTPHeaderFields?.isEmpty != false)
    }

    @Test("follows safe redirects after validating each hop")
    func followsSafeRedirects() async throws {
        let fetch = FetchSequence([
            makeFetchResponse(
                url: "https://example.com/file",
                statusCode: 302,
                headers: ["Location": "https://cdn.example.com/file"]
            ),
            makeFetchResponse(url: "https://cdn.example.com/file", body: Data("ok".utf8)),
        ])

        let response = try await fetchWithValidatedRedirects(
            url: "https://example.com/file",
            fetch: fetch.fetch
        )

        #expect(response.statusCode == 200)

        let requests = await fetch.requests()
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://example.com/file",
            "https://cdn.example.com/file",
        ])
    }

    @Test("rejects redirect to private address before requesting it")
    func rejectsPrivateRedirectBeforeRequestingIt() async throws {
        let fetch = FetchSequence([
            makeFetchResponse(
                url: "https://evil.com/redirect",
                statusCode: 302,
                headers: ["Location": "http://169.254.169.254/latest/meta-data/"]
            ),
        ])

        do {
            _ = try await fetchWithValidatedRedirects(
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

    @Test("resolves relative redirect targets against current URL")
    func resolvesRelativeRedirectTargets() async throws {
        let fetch = FetchSequence([
            makeFetchResponse(
                url: "https://example.com/start",
                statusCode: 302,
                headers: ["Location": "/internal"]
            ),
            makeFetchResponse(url: "https://example.com/internal", body: Data("ok".utf8)),
        ])

        _ = try await fetchWithValidatedRedirects(
            url: "https://example.com/start",
            fetch: fetch.fetch
        )

        let requests = await fetch.requests()
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://example.com/start",
            "https://example.com/internal",
        ])
    }

    @Test("rejects once redirect limit is exceeded")
    func rejectsWhenRedirectLimitExceeded() async throws {
        let fetch = RepeatingRedirectFetch()

        do {
            _ = try await fetchWithValidatedRedirects(
                url: "https://example.com/start",
                maxRedirects: 2,
                fetch: fetch.fetch
            )
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.message == "Too many redirects (max 2)")
            #expect(await fetch.requestCount() == 3)
        }
    }
}

actor FetchSequence {
    private var responses: [FetchResponse]
    private var capturedRequests: [URLRequest] = []

    init(_ responses: [FetchResponse]) {
        self.responses = responses
    }

    nonisolated var fetch: FetchFunction {
        { request in
            try await self.next(request)
        }
    }

    private func next(_ request: URLRequest) throws -> FetchResponse {
        capturedRequests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }

    func requests() -> [URLRequest] {
        capturedRequests
    }
}

private actor RepeatingRedirectFetch {
    private var capturedRequests: [URLRequest] = []

    nonisolated var fetch: FetchFunction {
        { request in
            try await self.next(request)
        }
    }

    private func next(_ request: URLRequest) throws -> FetchResponse {
        capturedRequests.append(request)
        return makeFetchResponse(
            url: request.url?.absoluteString ?? "https://example.com/start",
            statusCode: 302,
            headers: ["Location": "https://example.com/next"]
        )
    }

    func requestCount() -> Int {
        capturedRequests.count
    }
}

func makeFetchResponse(
    url: String,
    statusCode: Int = 200,
    headers: [String: String] = [:],
    body: Data = Data()
) -> FetchResponse {
    let responseURL = URL(string: url)!
    let httpResponse = HTTPURLResponse(
        url: responseURL,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!

    return FetchResponse(body: .data(body), urlResponse: httpResponse)
}
