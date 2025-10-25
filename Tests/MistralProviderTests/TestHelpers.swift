import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import MistralProvider

struct HTTPTestHelpers {
    static let chatURL = URL(string: "https://api.mistral.ai/v1/chat/completions")!
    static let embeddingURL = URL(string: "https://api.mistral.ai/v1/embeddings")!
}

actor RequestRecorder {
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func all() -> [URLRequest] {
        requests
    }

    func first() -> URLRequest? {
        requests.first
    }
}

actor ResponseBox {
    private var response: FetchResponse

    init(initial: FetchResponse) {
        self.response = initial
    }

    func setJSON(url: URL, statusCode: Int = 200, body: Any, headers: [String: String]? = nil) {
        let data = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        var headerFields: [String: String] = [
            "Content-Type": "application/json",
            "Content-Length": String(data.count)
        ]
        if let headers {
            for (key, value) in headers {
                headerFields[key] = value
            }
        }
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        response = FetchResponse(body: .data(data), urlResponse: httpResponse)
    }

    func setStream(url: URL, statusCode: Int = 200, chunks: [String], headers: [String: String]? = nil) {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks {
                continuation.yield(Data(chunk.utf8))
            }
            continuation.finish()
        }

        var headerFields: [String: String] = [
            "Content-Type": "text/event-stream"
        ]
        if let headers {
            for (key, value) in headers {
                headerFields[key] = value
            }
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!

        response = FetchResponse(body: .stream(stream), urlResponse: httpResponse)
    }

    func value() -> FetchResponse {
        response
    }
}

final class SequentialIDGenerator: @unchecked Sendable {
    private var counter: Int = 0
    private let lock = NSLock()

    @Sendable func callAsFunction() -> String {
        lock.lock()
        defer { lock.unlock() }
        let current = counter
        counter += 1
        if current == 0 {
            return "id-0"
        }
        return "id-\(current)"
    }
}

func decodeJSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody else {
        return [:]
    }
    return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
}

func collectStream(_ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
    var parts: [LanguageModelV3StreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

func string(from jsonValue: JSONValue) throws -> String {
    let any = jsonValueToFoundation(jsonValue)
    let data = try JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? ""
}
