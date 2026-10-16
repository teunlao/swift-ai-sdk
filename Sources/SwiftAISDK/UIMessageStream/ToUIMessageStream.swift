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
    let converted = AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
        let task = Task {
            do {
                for try await part in stream {
                    let metadata = options.messageMetadata?(part)
                    let chunk = toUIMessageChunk(part, options: ToUIMessageChunkOptions(
                        tools: tools, sendReasoning: options.sendReasoning, sendSources: options.sendSources,
                        sendStart: options.sendStart, sendFinish: options.sendFinish,
                        onError: mapError, messageMetadata: metadata, responseMessageId: responseId
                    ))
                    let isStepEnd: Bool
                    switch part {
                    case .finishStep: isStepEnd = true
                    default: isStepEnd = false
                    }
                    if let chunk, !isStepEnd { continuation.yield(chunk) }
                    if let metadata, metadata != .null {
                        switch part {
                        case .start, .finish: break
                        default: continuation.yield(.messageMetadata(metadata))
                        }
                    }
                    if let chunk, isStepEnd { continuation.yield(chunk) }
                    switch part {
                    case .finish: outcome.set(.completed)
                    case .abort: outcome.set(.aborted)
                    case .error(let error): outcome.set(.failed(error: error))
                    default: break
                    }
                }
                continuation.finish()
            } catch {
                if !Task.isCancelled { outcome.fail(error) }
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
    }
    return handleUIMessageStreamFinish(
        stream: converted, messageId: responseId ?? options.generateMessageId?(),
        originalMessages: options.originalMessages ?? [],
        onStepFinish: options.onStepFinish, onFinish: options.onFinish, onError: { _ = mapError($0) },
        onStepEnd: options.onStepEnd, onEnd: options.onEnd, getOutcome: { outcome.get() }
    )
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
