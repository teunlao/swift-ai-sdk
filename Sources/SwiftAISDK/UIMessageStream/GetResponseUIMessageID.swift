import Foundation
import AISDKProviderUtils

/**
 Determines the response UI message identifier.

 Port of `@ai-sdk/ai/src/ui-message-stream/get-response-ui-message-id.ts`.
 */
public enum ResponseMessageIdentifier {
    case literal(String)
    case generator(IDGenerator)
}

public func getResponseUIMessageId(
    originalMessages: [UIMessage]?,
    responseMessageId: ResponseMessageIdentifier
) -> String? {
    guard let originalMessages else {
        return nil
    }

    guard let lastMessage = originalMessages.last, lastMessage.role == .assistant else {
        switch responseMessageId {
        case .literal(let id):
            return id
        case .generator(let generator):
            return generator()
        }
    }

    return lastMessage.id
}

public func getResponseUIMessageId(
    originalMessages: [UIMessage]?,
    responseMessageId: String
) -> String? {
    getResponseUIMessageId(
        originalMessages: originalMessages,
        responseMessageId: .literal(responseMessageId)
    )
}

public func getResponseUIMessageId(
    originalMessages: [UIMessage]?,
    responseMessageId: @escaping IDGenerator
) -> String? {
    getResponseUIMessageId(
        originalMessages: originalMessages,
        responseMessageId: .generator(responseMessageId)
    )
}

