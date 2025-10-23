import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

/// Azure OpenAI-specific tools.
/// Mirrors `packages/azure/src/azure-openai-tools.ts`.
public struct AzureProviderTools: Sendable {
    public init() {}

    @discardableResult
    public func codeInterpreter(_ args: OpenAICodeInterpreterArgs = .init()) -> Tool {
        openaiCodeInterpreterToolFactory(args)
    }

    @discardableResult
    public func fileSearch(_ args: OpenAIFileSearchArgs) -> Tool {
        openaiFileSearchToolFactory(args)
    }

    @discardableResult
    public func imageGeneration(_ args: OpenAIImageGenerationArgs = .init()) -> Tool {
        openaiImageGenerationToolFactory(args)
    }
}

/// Default Azure tool facade (parity with TS export).
public let azureOpenaiTools = AzureProviderTools()
