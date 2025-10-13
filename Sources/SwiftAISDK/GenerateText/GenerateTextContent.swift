/**
 Content part type representing different types of content in a generation response.

 Port of `@ai-sdk/ai/src/generate-text/content-part.ts`.

 This enum represents all possible content parts that can appear in a generation
 response, including text, reasoning, sources, files, tool calls, tool results,
 tool errors, and tool approval requests.

 ## File Naming

 File is named `GenerateTextContent.swift` (not `ContentPart.swift`) to avoid
 conflict with `ProviderUtils/ContentPart.swift`, which contains individual
 content part type definitions (TextPart, ImagePart, etc.) from the
 `@ai-sdk/provider-utils` package.

 In TypeScript, these exist in different npm packages and thus have separate
 namespaces (`@ai-sdk/provider-utils` vs `@ai-sdk/ai`), but in Swift we have
 a single module (SwiftAISDK). The public API type name `ContentPart` matches
 the upstream exactly, maintaining 100% parity.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Content part representing different types of content in a response
public enum ContentPart: Sendable {
    /// Plain text content with optional provider metadata
    case text(text: String, providerMetadata: ProviderMetadata?)

    /// Reasoning output (model's chain of thought)
    case reasoning(ReasoningOutput)

    /// Source content with attribution
    case source(type: String, source: Source)

    /// Generated file with optional provider metadata
    case file(file: GeneratedFile, providerMetadata: ProviderMetadata?)

    /// Tool call (static or dynamic)
    case toolCall(TypedToolCall, providerMetadata: ProviderMetadata?)

    /// Tool result (static or dynamic)
    case toolResult(TypedToolResult, providerMetadata: ProviderMetadata?)

    /// Tool error (static or dynamic)
    case toolError(TypedToolError, providerMetadata: ProviderMetadata?)

    /// Tool approval request
    case toolApprovalRequest(ToolApprovalRequestOutput)
}

// MARK: - Computed Properties

extension ContentPart {
    /// The type identifier for this content part
    public var type: String {
        switch self {
        case .text:
            return "text"
        case .reasoning:
            return "reasoning"
        case .source:
            return "source"
        case .file:
            return "file"
        case .toolCall:
            return "tool-call"
        case .toolResult:
            return "tool-result"
        case .toolError:
            return "tool-error"
        case .toolApprovalRequest:
            return "tool-approval-request"
        }
    }
}
