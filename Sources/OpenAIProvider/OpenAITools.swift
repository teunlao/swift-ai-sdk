import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAITools: Sendable {
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

    @discardableResult
    public func mcp(_ args: OpenAIMCPArgs) -> Tool {
        openaiMcpToolFactory(args)
    }

    @discardableResult
    public func localShell(_ options: ProviderToolFactoryWithOutputSchemaOptions = .init()) -> Tool {
        openaiLocalShellTool(options)
    }

    @discardableResult
    public func shell(_ options: ProviderToolFactoryWithOutputSchemaOptions = .init()) -> Tool {
        openaiShellTool(options)
    }

    @discardableResult
    public func applyPatch(_ options: ProviderToolFactoryWithOutputSchemaOptions = .init()) -> Tool {
        openaiApplyPatchTool(options)
    }

    @discardableResult
    public func webSearch(_ args: OpenAIWebSearchArgs = .init()) -> Tool {
        openaiWebSearchToolFactory(args)
    }

    @discardableResult
    public func webSearchPreview(_ args: OpenAIWebSearchPreviewArgs = .init()) -> Tool {
        openaiWebSearchPreviewToolFactory(args)
    }
}

public let openaiTools = OpenAITools()
