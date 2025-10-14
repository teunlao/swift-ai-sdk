import Foundation
import AISDKProviderUtils

/**
 Creates a simulated readable stream that emits provided chunks with optional delays.

 Port of `@ai-sdk/ai/src/util/simulate-readable-stream.ts`.
 */
public struct SimulateReadableStreamInternalOptions: Sendable {
    public let delay: @Sendable (Int?) async throws -> Void

    public init(delay: @escaping @Sendable (Int?) async throws -> Void) {
        self.delay = delay
    }
}

public func simulateReadableStream<T: Sendable>(
    chunks: [T],
    initialDelayInMs: Int? = 0,
    chunkDelayInMs: Int? = 0,
    _internal: SimulateReadableStreamInternalOptions? = nil
) -> AsyncThrowingStream<T, Error> {
    let delayFunction: @Sendable (Int?) async throws -> Void

    if let customDelay = _internal?.delay {
        delayFunction = customDelay
    } else {
        delayFunction = { milliseconds in
            try await delay(milliseconds)
        }
    }

    return AsyncThrowingStream<T, Error> { continuation in
        Task {
            do {
                for (index, chunk) in chunks.enumerated() {
                    let delayValue = index == 0 ? initialDelayInMs : chunkDelayInMs
                    try await delayFunction(delayValue)
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
