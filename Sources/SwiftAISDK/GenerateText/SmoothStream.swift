/**
 Smooths text streaming output for better user experience.

 Port of `@ai-sdk/ai/src/generate-text/smooth-stream.ts`.

 The smooth stream function takes a stream of text chunks and applies a chunking
 strategy (word, line, regex, or custom function) with optional delays between
 chunks to create a smoother streaming experience.

 **TypeScript adaptation**:
 - `TransformStream` → function returning `AsyncThrowingStream`
 - Generic `TOOLS` type → uses concrete `TextStreamPart` enum
 - `ReadableStream` → `AsyncSequence`
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - ChunkingMode

/// Chunking mode for smooth streaming.
public enum ChunkingMode: Sendable {
    /// Stream word by word (default).
    case word
    /// Stream line by line.
    case line
    /// Custom regex pattern for chunking.
    case regex(NSRegularExpression)

    /// Get the regular expression for this chunking mode.
    fileprivate var regex: NSRegularExpression {
        switch self {
        case .word:
            return try! NSRegularExpression(pattern: "\\S+\\s+", options: [.dotMatchesLineSeparators])
        case .line:
            return try! NSRegularExpression(pattern: "\\n+", options: [.dotMatchesLineSeparators])
        case .regex(let regex):
            return regex
        }
    }
}

// MARK: - ChunkDetector

/// Detects the first chunk in a buffer.
///
/// - Parameter buffer: The buffer to detect the first chunk in.
/// - Returns: The first detected chunk, or `nil` if no chunk was detected.
public typealias ChunkDetector = @Sendable (String) -> String?

// MARK: - Chunking Strategy

/// Strategy for detecting chunks in the buffer.
public enum ChunkingStrategy: Sendable {
    /// Predefined chunking mode.
    case mode(ChunkingMode)
    /// Custom chunk detector function.
    case detector(ChunkDetector)
}

// MARK: - Internal Options

/// Internal options for smooth stream (for testing).
public struct SmoothStreamInternalOptions: Sendable {
    /// Custom delay function (for testing).
    public let delay: @Sendable (Int?) async -> Void

    public init(delay: @escaping @Sendable (Int?) async -> Void) {
        self.delay = delay
    }
}

// MARK: - Smooth Stream Function

/**
 Smooths text streaming output.

 - Parameters:
   - stream: The input stream of TextStreamPart to smooth.
   - delayInMs: The delay in milliseconds between each chunk. Defaults to 10ms. Can be set to `nil` to skip the delay.
   - chunking: Controls how the text is chunked for streaming. Use `.mode(.word)` to stream word by word (default), `.mode(.line)` to stream line by line, or provide a custom strategy for custom chunking.
   - _internal: Internal options for testing. May change without notice.

 - Returns: An `AsyncThrowingStream` of smoothed `TextStreamPart`.

 **Usage**:
 ```swift
 let smoothed = try smoothStream(
     stream: originalStream,
     delayInMs: 10,
     chunking: .mode(.word)
 )

 for try await part in smoothed {
     // Process smoothed stream parts
 }
 ```
 */
public func smoothStream<S: AsyncSequence & Sendable>(
    stream: S,
    delayInMs: Int? = 10,
    chunking: ChunkingStrategy = .mode(.word),
    _internal: SmoothStreamInternalOptions? = nil
) throws -> AsyncThrowingStream<TextStreamPart, Error> where S.Element == TextStreamPart {

    // Determine the chunk detector based on chunking strategy
    let detectChunk: ChunkDetector

    switch chunking {
    case .detector(let detector):
        // Use custom detector directly - validation happens in the main loop
        detectChunk = detector

    case .mode(let mode):
        let chunkingRegex = mode.regex

        detectChunk = { buffer in
            let range = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
            guard let match = chunkingRegex.firstMatch(in: buffer, options: [], range: range) else {
                return nil
            }

            let matchRange = Range(match.range, in: buffer)!
            let prefix = String(buffer[..<matchRange.lowerBound])
            let matchText = String(buffer[matchRange])
            return prefix + matchText
        }
    }

    // Return transformed stream
    return AsyncThrowingStream { continuation in
            Task { @Sendable in
                var buffer = ""
                var id = ""
                var isReasoning = false
                // Metadata of the delta the buffer came from; one output part carries one delta's metadata.
                var providerMetadata: ProviderMetadata?

                func part(_ text: String) -> TextStreamPart {
                    isReasoning
                        ? .reasoningDelta(id: id, text: text, providerMetadata: providerMetadata)
                        : .textDelta(id: id, text: text, providerMetadata: providerMetadata)
                }

                func flushBuffer() {
                    if !buffer.isEmpty || providerMetadata != nil {
                        continuation.yield(part(buffer))
                    }
                    buffer = ""
                    providerMetadata = nil
                }

                let delayFn: @Sendable (Int?) async -> Void
                if let internalOptions = _internal {
                    delayFn = internalOptions.delay
                } else {
                    delayFn = { ms in
                        if let ms = ms, ms > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                        }
                    }
                }

                do {
                    for try await chunk in stream {
                        let chunkId: String
                        let text: String
                        let metadata: ProviderMetadata?
                        let chunkIsReasoning: Bool
                        switch chunk {
                        case .textDelta(let deltaId, let deltaText, let deltaMetadata):
                            (chunkId, text, metadata, chunkIsReasoning) = (deltaId, deltaText, deltaMetadata, false)
                        case .reasoningDelta(let deltaId, let deltaText, let deltaMetadata):
                            (chunkId, text, metadata, chunkIsReasoning) = (deltaId, deltaText, deltaMetadata, true)
                        default:
                            flushBuffer()
                            continuation.yield(chunk)
                            continue
                        }

                        // A metadata-only delta passes through on its own.
                        if text.isEmpty && metadata != nil {
                            flushBuffer()
                            continuation.yield(chunk)
                            continue
                        }

                        if !buffer.isEmpty,
                           chunkIsReasoning != isReasoning || chunkId != id || providerMetadata != nil || metadata != nil {
                            flushBuffer()
                        }

                        buffer += text
                        id = chunkId
                        isReasoning = chunkIsReasoning
                        providerMetadata = metadata

                        while let detectedChunk = detectChunk(buffer) {
                            guard !detectedChunk.isEmpty else {
                                throw NSError(
                                    domain: "SmoothStream",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Chunking function must return a non-empty string."]
                                )
                            }

                            guard buffer.hasPrefix(detectedChunk) else {
                                throw NSError(
                                    domain: "SmoothStream",
                                    code: -1,
                                    userInfo: [
                                        NSLocalizedDescriptionKey:
                                            "Chunking function must return a match that is a prefix of the buffer. " +
                                            "Received: \"\(detectedChunk)\" expected to start with \"\(buffer)\""
                                    ]
                                )
                            }

                            continuation.yield(part(detectedChunk))
                            buffer = String(buffer.dropFirst(detectedChunk.count))
                            await delayFn(delayInMs)
                        }

                        if buffer.isEmpty {
                            providerMetadata = nil
                        }
                    }

                    flushBuffer()

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
}
