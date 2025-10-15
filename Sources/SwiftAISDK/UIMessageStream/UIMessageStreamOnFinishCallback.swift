import Foundation

/**
 Completion callback invoked when a UI message stream finishes.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-stream-on-finish-callback.ts`.
 */
public typealias UIMessageStreamOnFinishCallback<Message: UIMessageConvertible> =
    @Sendable (UIMessageStreamFinishEvent<Message>) async -> Void

public struct UIMessageStreamFinishEvent<Message: UIMessageConvertible>: Sendable, Equatable {
    public let messages: [Message]
    public let isContinuation: Bool
    public let isAborted: Bool
    public let responseMessage: Message

    public init(
        messages: [Message],
        isContinuation: Bool,
        isAborted: Bool,
        responseMessage: Message
    ) {
        self.messages = messages
        self.isContinuation = isContinuation
        self.isAborted = isAborted
        self.responseMessage = responseMessage
    }
}
