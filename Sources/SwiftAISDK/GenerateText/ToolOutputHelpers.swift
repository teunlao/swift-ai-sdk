import AISDKProvider
import AISDKProviderUtils

func makeToolContentPart(
    output: ToolOutput,
    tools: ToolSet?
) -> ToolContentPart {
    switch output {
    case .result(let result):
        let modelOutput = createToolModelOutput(
            output: result.output,
            tool: tools?[result.toolName],
            errorMode: .none
        )
        let part = ToolResultPart(
            toolCallId: result.toolCallId,
            toolName: result.toolName,
            output: modelOutput,
            providerOptions: nil
        )
        return .toolResult(part)

    case .error(let error):
        let modelOutput = createToolModelOutput(
            output: error.error,
            tool: tools?[error.toolName],
            errorMode: .json
        )
        let part = ToolResultPart(
            toolCallId: error.toolCallId,
            toolName: error.toolName,
            output: modelOutput,
            providerOptions: nil
        )
        return .toolResult(part)
    }
}
