import Foundation
@testable import SwiftAISDK

/**
 Mock implementation of `StreamTextResponseWriter` for testing.

 Port of `@ai-sdk/ai/src/test/mock-server-response.ts`.
 */
final class MockStreamTextResponseWriter: StreamTextResponseWriter, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MockStreamTextResponseWriter")

    private var internalStatusCode: Int = 0
    private var internalStatusText: String?
    private var internalHeaders: [String: String] = [:]
    private var internalChunks: [Data] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isEnded = false

    func writeHead(
        status: Int,
        statusText: String?,
        headers: [String: String]
    ) {
        queue.sync {
            internalStatusCode = status
            internalStatusText = statusText
            internalHeaders = headers
        }
    }

    func write(_ data: Data) {
        queue.sync {
            internalChunks.append(data)
        }
    }

    func end() {
        let pendingContinuations: [CheckedContinuation<Void, Never>] = queue.sync {
            guard !isEnded else {
                return []
            }

            isEnded = true
            let continuationsCopy = continuations
            continuations.removeAll()
            return continuationsCopy
        }

        for continuation in pendingContinuations {
            continuation.resume()
        }
    }

    func waitForEnd() async {
        await withCheckedContinuation { continuation in
            var shouldResumeImmediately = false

            queue.sync {
                if isEnded {
                    shouldResumeImmediately = true
                } else {
                    continuations.append(continuation)
                }
            }

            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }

    var statusCode: Int {
        queue.sync { internalStatusCode }
    }

    var statusMessage: String? {
        queue.sync { internalStatusText }
    }

    var headers: [String: String] {
        queue.sync { internalHeaders }
    }

    var writtenChunks: [Data] {
        queue.sync { internalChunks }
    }

    func decodedChunks() -> [String] {
        queue.sync {
            internalChunks.map { String(decoding: $0, as: UTF8.self) }
        }
    }
}
