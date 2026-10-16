import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A citation supporting generated text.

 Port of `@ai-sdk/ai/src/types/citation.ts`.
 */
public typealias Citation = LanguageModelV4Citation

/**
 Content part of a generation response.

 Port of `@ai-sdk/ai/src/generate-text/content-part.ts`. Named
 `GenerateTextContent.swift` to avoid clashing with `ContentPart.swift` in
 `AISDKProviderUtils`.
 */
public enum ContentPart: Sendable {
    case text(text: String, citations: [Citation]? = nil, providerMetadata: ProviderMetadata?)

    case custom(kind: String, providerMetadata: ProviderMetadata?)

    case reasoning(ReasoningOutput)

    case reasoningFile(file: GeneratedFile, providerMetadata: ProviderMetadata?)

    case source(type: String, source: Source)

    case file(file: GeneratedFile, providerMetadata: ProviderMetadata?)

    case toolCall(TypedToolCall, providerMetadata: ProviderMetadata?)

    case toolResult(TypedToolResult, providerMetadata: ProviderMetadata?)

    case toolError(TypedToolError, providerMetadata: ProviderMetadata?)

    case toolApprovalRequest(ToolApprovalRequestOutput)

    case toolApprovalResponse(ToolApprovalResponseOutput)
}

extension ContentPart {
    public var type: String {
        switch self {
        case .text: return "text"
        case .custom: return "custom"
        case .reasoning: return "reasoning"
        case .reasoningFile: return "reasoning-file"
        case .source: return "source"
        case .file: return "file"
        case .toolCall: return "tool-call"
        case .toolResult: return "tool-result"
        case .toolError: return "tool-error"
        case .toolApprovalRequest: return "tool-approval-request"
        case .toolApprovalResponse: return "tool-approval-response"
        }
    }
}
