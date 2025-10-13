/**
 Consumes an AsyncSequence until it's fully read.

 Port of `@ai-sdk/ai/src/util/consume-stream.ts`.

 This function iterates through the stream chunk by chunk until the stream is exhausted.
 It doesn't process or return the data from the stream; it simply ensures
 that the entire stream is consumed.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Consumes an AsyncSequence until completion.

 - Parameters:
   - stream: The AsyncSequence to consume
   - onError: Optional error handler called if stream throws

 - Note: In TypeScript this consumes a ReadableStream. In Swift we use AsyncSequence
         which is the idiomatic equivalent for async iteration.
 */
public func consumeStream<S: AsyncSequence>(
    stream: S,
    onError: (@Sendable (Error) -> Void)? = nil
) async {
    do {
        for try await _ in stream {
            // Simply consume chunks without processing
        }
    } catch {
        onError?(error)
    }
}
