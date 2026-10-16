import Foundation
import AISDKProvider

/**
 Converts the streamed input of a JSON response tool into text parts, so the SDK
 can parse it as structured output when a provider cannot use native structured
 output for the request.

 Conversational text is suppressed. Application tool calls pass through for the
 caller to execute. A response containing only the JSON tool finishes with
 `stop`; a response containing application calls keeps its finish reason.

 Port of `@ai-sdk/provider-utils/src/convert-json-response-tool-stream.ts`.
 */
public func convertJsonResponseToolStream(
    _ stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>,
    toolName: String
) -> AsyncThrowingStream<LanguageModelV4StreamPart, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var converter = JsonResponseToolStreamConverter(toolName: toolName)
            do {
                for try await part in stream {
                    for converted in converter.convert(part) {
                        continuation.yield(converted)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}

private struct JsonResponseToolStreamConverter {
    let toolName: String
    private var responseToolIds: Set<String> = []
    private var responseToolsWithDeltas: Set<String> = []
    private var hasResponseTool = false
    private var hasApplicationTool = false

    init(toolName: String) {
        self.toolName = toolName
    }

    mutating func convert(_ part: LanguageModelV4StreamPart) -> [LanguageModelV4StreamPart] {
        switch part {
        case .textStart, .textDelta, .textEnd:
            // The response tool supplies the output; omit conversational text.
            return []

        case let .toolInputStart(id, partToolName, providerMetadata, _, _, _, _) where partToolName == toolName:
            responseToolIds.insert(id)
            return [.textStart(id: id, providerMetadata: providerMetadata)]

        case let .toolInputDelta(id, delta, providerMetadata) where responseToolIds.contains(id):
            if !delta.isEmpty {
                responseToolsWithDeltas.insert(id)
            }
            return [.textDelta(id: id, delta: delta, providerMetadata: providerMetadata)]

        case let .toolInputEnd(id, _) where responseToolIds.contains(id):
            return []

        case .toolCall(let toolCall) where toolCall.toolName == toolName:
            var parts: [LanguageModelV4StreamPart] = []
            if !responseToolsWithDeltas.contains(toolCall.toolCallId) {
                parts.append(.textDelta(
                    id: toolCall.toolCallId,
                    delta: toolCall.input,
                    providerMetadata: toolCall.providerMetadata
                ))
            }
            parts.append(.textEnd(id: toolCall.toolCallId, providerMetadata: toolCall.providerMetadata))
            hasResponseTool = true
            return parts

        case .toolCall(let toolCall):
            if toolCall.providerExecuted != true {
                hasApplicationTool = true
            }
            return [part]

        case let .finish(finishReason, usage, providerMetadata)
            where hasResponseTool && !hasApplicationTool && finishReason.unified == .toolCalls:
            return [.finish(
                finishReason: LanguageModelV4FinishReason(unified: .stop, raw: finishReason.raw),
                usage: usage,
                providerMetadata: providerMetadata
            )]

        default:
            return [part]
        }
    }
}
