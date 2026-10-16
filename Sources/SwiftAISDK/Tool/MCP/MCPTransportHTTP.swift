import Foundation
import AISDKProviderUtils

internal actor MCPTransportAuthorization {
    private var pending: Task<AuthResult, Error>?

    func authorize(_ operation: @escaping @Sendable () async throws -> AuthResult) async throws -> AuthResult {
        if let pending { return try await pending.value }
        let task = Task { try await operation() }
        pending = task
        defer { pending = nil }
        return try await task.value
    }
}

internal final class MCPRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let reject = MCPRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

internal func mcpSessionFetch(_ session: URLSession) -> FetchFunction {
    { request in
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: request.fetchRedirectMode == .follow ? nil : MCPRedirectDelegate.reject
        )
        return FetchResponse(body: .stream(mcpDataStream(from: bytes)), urlResponse: response)
    }
}

internal func fetchMCPResponse(_ request: URLRequest, fetch: FetchFunction, redirect: MCPRedirectMode) async throws -> (ProviderHTTPResponseBody, URLResponse) {
    var prepared = request
    prepared.fetchRedirectMode = redirect == .error ? .error : .follow
    try Task.checkCancellation()
    let response = try await fetch(prepared)
    if Task.isCancelled {
        if let url = request.url, let http = response.urlResponse as? HTTPURLResponse {
            await cancelResponseBody(.init(url: url, httpResponse: http, body: response.body))
        }
        throw CancellationError()
    }
    return (response.body, response.urlResponse)
}

internal func mcpOAuthFetch(_ fetch: @escaping FetchFunction) -> MCPFetchFunction {
    { request in
        let response = try await fetch(request)
        guard let http = response.urlResponse as? HTTPURLResponse else {
            throw MCPClientError(message: "Invalid OAuth HTTP response")
        }
        return (try await response.body.collectData(), http)
    }
}

// AsyncThrowingStream pulls this iterator from one consumer task.
private final class MCPByteReader: @unchecked Sendable {
    private var iterator: URLSession.AsyncBytes.Iterator

    init(_ bytes: URLSession.AsyncBytes) { iterator = bytes.makeAsyncIterator() }

    func next() async throws -> Data? {
        var buffer = Data()
        while let byte = try await iterator.next() {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 1024 || byte == 10 { return buffer }
        }
        return buffer.isEmpty ? nil : buffer
    }
}

internal func mcpDataStream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<Data, Error> {
    let reader = MCPByteReader(bytes)
    return AsyncThrowingStream(unfolding: { try await reader.next() })
}
