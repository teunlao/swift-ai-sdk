import Testing
import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("getResponseUIMessageId")
struct GetResponseUIMessageIDTests {
    private let generator: IDGenerator = { "new-id" }

    @Test("should return nil when originalMessages is nil")
    func returnsNilWhenOriginalMessagesNil() {
        let result = getResponseUIMessageId(
            originalMessages: (nil as [UIMessage]?),
            responseMessageId: generator
        )
        #expect(result == nil)
    }

    @Test("should return last assistant message id when present")
    func returnsLastAssistantMessageId() {
        let messages = [
            UIMessage(id: "msg-1", role: .user, parts: []),
            UIMessage(id: "msg-2", role: .assistant, parts: [])
        ]

        let result = getResponseUIMessageId(
            originalMessages: messages,
            responseMessageId: generator
        )

        #expect(result == "msg-2")
    }

    @Test("should generate new id when last message is not assistant")
    func generatesNewIdWhenLastMessageNotAssistant() {
        let messages = [
            UIMessage(id: "msg-1", role: .assistant, parts: []),
            UIMessage(id: "msg-2", role: .user, parts: [])
        ]

        let result = getResponseUIMessageId(
            originalMessages: messages,
            responseMessageId: generator
        )

        #expect(result == "new-id")
    }

    @Test("should generate new id when messages array is empty")
    func generatesNewIdWhenMessagesEmpty() {
        let result = getResponseUIMessageId(
            originalMessages: [UIMessage](),
            responseMessageId: generator
        )

        #expect(result == "new-id")
    }

    @Test("should use the responseMessageId when it is a string")
    func usesLiteralResponseMessageId() {
        let result = getResponseUIMessageId(
            originalMessages: [UIMessage](),
            responseMessageId: "response-id"
        )

        #expect(result == "response-id")
    }
}
