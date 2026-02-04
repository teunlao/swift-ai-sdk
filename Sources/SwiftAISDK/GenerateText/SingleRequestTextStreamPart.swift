import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Stream part emitted during a single generate-text request.

 Port of `@ai-sdk/ai/src/generate-text/run-tools-transformation.ts`
 (`SingleRequestTextStreamPart` type).

 This enum mirrors the upstream union of stream chunk variants that flow through
 the tool orchestration pipeline before higher-level transformations (smooth
 streaming, response assembly, etc.). Each case preserves the upstream shape so
 subsequent stages can rely on identical data.
 */
public enum SingleRequestTextStreamPart: Sendable {
    // MARK: - Text Events

    case textStart(id: String, providerMetadata: ProviderMetadata?)
    case textDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
    case textEnd(id: String, providerMetadata: ProviderMetadata?)

    // MARK: - Reasoning Events

    case reasoningStart(id: String, providerMetadata: ProviderMetadata?)
    case reasoningDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
    case reasoningEnd(id: String, providerMetadata: ProviderMetadata?)

    // MARK: - Tool Input Events

    case toolInputStart(
        id: String,
        toolName: String,
        providerMetadata: ProviderMetadata?,
        providerExecuted: Bool?,
        dynamic: Bool?,
        title: String?
    )
    case toolInputDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
    case toolInputEnd(id: String, providerMetadata: ProviderMetadata?)

    // MARK: - Tool Interaction Events

    case toolCall(TypedToolCall)
    case toolResult(TypedToolResult)
    case toolError(TypedToolError)
    case toolApprovalRequest(ToolApprovalRequestOutput)

    // MARK: - Content & Metadata

    case source(Source)
    case file(GeneratedFile)
    case streamStart(warnings: [SharedV3Warning])
    case responseMetadata(id: String?, timestamp: Date?, modelId: String?)
    case finish(
        finishReason: FinishReason,
        rawFinishReason: String?,
        usage: LanguageModelUsage,
        providerMetadata: ProviderMetadata?
    )

    // MARK: - Control / Diagnostics

    case error(any Error)
    case raw(JSONValue)
}
