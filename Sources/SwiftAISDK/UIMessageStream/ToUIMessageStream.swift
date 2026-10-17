import Foundation
import AISDKProviderUtils

public func toUIMessageStream<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<TextStreamPart, Error>,
    tools: ToolSet? = nil,
    options: UIMessageStreamOptions<Message> = UIMessageStreamOptions()
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    let responseId = options.generateMessageId.flatMap {
        getResponseUIMessageId(originalMessages: options.originalMessages, responseMessageId: $0)
    }
    let outcome = UIStreamSourceOutcome()
    let mapError = options.onError ?? { _ in "An error occurred." }
    let source = UIStreamSource(stream)
    // Pull-based: a part is read from `stream` only when the UI stream's consumer asks for a chunk.
    let converted = AsyncThrowingStream<AnyUIMessageChunk, Error>(unfolding: {
        try await source.next(outcome: outcome) { part in
            let metadata = options.messageMetadata?(part)
            let chunk = toUIMessageChunk(part, options: ToUIMessageChunkOptions(
                tools: tools, sendReasoning: options.sendReasoning, sendSources: options.sendSources,
                sendStart: options.sendStart, sendFinish: options.sendFinish,
                onError: mapError, messageMetadata: metadata, responseMessageId: responseId
            ))
            var chunks: [AnyUIMessageChunk] = []
            let isStepEnd: Bool
            switch part {
            case .finishStep: isStepEnd = true
            default: isStepEnd = false
            }
            if let chunk, !isStepEnd { chunks.append(chunk) }
            if let metadata, metadata != .null {
                switch part {
                case .start, .finish: break
                default: chunks.append(.messageMetadata(metadata))
                }
            }
            // Step metadata is applied before the boundary triggers a UI snapshot.
            if let chunk, isStepEnd { chunks.append(chunk) }
            switch part {
            case .finish: outcome.set(.completed)
            case .abort: outcome.set(.aborted)
            case .error(let error): outcome.set(.failed(error: error))
            default: break
            }
            return chunks
        }
    })
    return handleUIMessageStreamFinish(
        stream: converted, messageId: responseId ?? options.generateMessageId?(),
        originalMessages: options.originalMessages ?? [],
        onStepEnd: options.onStepEnd, onEnd: options.onEnd,
        onError: { _ = mapError($0) }, getOutcome: { outcome.get() }
    )
}

/// The single reader of the source parts; `next` is called by one consumer at a time.
private final class UIStreamSource: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<TextStreamPart, Error>.AsyncIterator
    private var pending: [AnyUIMessageChunk] = []

    init(_ stream: AsyncThrowingStream<TextStreamPart, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next(
        outcome: UIStreamSourceOutcome,
        convert: (TextStreamPart) -> [AnyUIMessageChunk]
    ) async throws -> AnyUIMessageChunk? {
        while pending.isEmpty {
            let part: TextStreamPart?
            do {
                part = try await iterator.next()
            } catch {
                if !Task.isCancelled { outcome.fail(error) }
                throw error
            }
            guard let part else { return nil }
            pending = convert(part)
        }
        return pending.removeFirst()
    }
}

private final class UIStreamSourceOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: UIMessageStreamOutcome = .unknown
    private var fatal = false

    func set(_ value: UIMessageStreamOutcome) {
        lock.lock()
        defer { lock.unlock() }
        if !fatal, outcome.status != "completed", outcome.status != "aborted",
           value.status != "unknown", outcome.status == "unknown" || value.status != "failed" {
            outcome = value
        }
    }

    func fail(_ error: Error) {
        lock.lock()
        outcome = .failed(error: error)
        fatal = true
        lock.unlock()
    }

    func get() -> UIMessageStreamOutcome {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }
}
