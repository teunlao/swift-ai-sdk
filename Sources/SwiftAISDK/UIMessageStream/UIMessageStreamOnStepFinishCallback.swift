import Foundation

/**
 Callback invoked when a step finishes during UI message streaming.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-stream-on-step-finish-callback.ts`.
 */
public typealias UIMessageStreamOnStepFinishCallback<Message: UIMessageConvertible> =
    @Sendable (UIMessageStreamStepFinishEvent<Message>) async throws -> Void

public struct UIMessageStreamStepFinishEvent<Message: UIMessageConvertible>: Sendable, Equatable {
    public let messages: [Message]
    public let isContinuation: Bool
    public let responseMessage: Message

    public init(
        messages: [Message],
        isContinuation: Bool,
        responseMessage: Message
    ) {
        self.messages = messages
        self.isContinuation = isContinuation
        self.responseMessage = responseMessage
    }
}

