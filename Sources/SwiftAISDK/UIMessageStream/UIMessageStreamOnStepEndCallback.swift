import Foundation

/**
 Callback invoked when a step ends during UI message streaming.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-stream-on-step-end-callback.ts`.
 */
public typealias UIMessageStreamOnStepEndCallback<Message: UIMessageConvertible> =
    @Sendable (UIMessageStreamStepEndEvent<Message>) async throws -> Void

public struct UIMessageStreamStepEndEvent<Message: UIMessageConvertible>: Sendable, Equatable {
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
