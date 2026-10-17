import Foundation

/**
 Callback invoked when a UI message stream ends.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-stream-on-end-callback.ts`.
 */
public typealias UIMessageStreamOnEndCallback<Message: UIMessageConvertible> =
    @Sendable (UIMessageStreamEndEvent<Message>) async throws -> Void

public enum UIMessageStreamOutcome: Sendable {
    case completed
    case failed(error: Error? = nil)
    case aborted
    case unknown

    public var status: String {
        switch self {
        case .completed: return "completed"
        case .failed: return "failed"
        case .aborted: return "aborted"
        case .unknown: return "unknown"
        }
    }
}

public struct UIMessageStreamEndEvent<Message: UIMessageConvertible>: Sendable {
    public let messages: [Message]
    public let isContinuation: Bool
    public let isAborted: Bool
    public let responseMessage: Message
    public let finishReason: FinishReason?
    public let isCancelled: Bool?
    public let outcome: UIMessageStreamOutcome

    public init(
        messages: [Message],
        isContinuation: Bool,
        isAborted: Bool,
        responseMessage: Message,
        finishReason: FinishReason? = nil,
        isCancelled: Bool? = nil,
        outcome: UIMessageStreamOutcome = .unknown
    ) {
        self.messages = messages
        self.isContinuation = isContinuation
        self.isAborted = isAborted
        self.responseMessage = responseMessage
        self.finishReason = finishReason
        self.isCancelled = isCancelled
        self.outcome = outcome
    }
}
