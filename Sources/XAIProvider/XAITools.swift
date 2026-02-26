import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAITools: Sendable {
    public init() {}

    @discardableResult
    public func webSearch(_ args: XAIWebSearchArgs = .init()) -> Tool {
        xaiWebSearchToolFactory(args)
    }

    @discardableResult
    public func xSearch(_ args: XAIXSearchArgs = .init()) -> Tool {
        xaiXSearchToolFactory(args)
    }

    @discardableResult
    public func codeExecution(_ options: ProviderToolFactoryWithOutputSchemaOptions = .init()) -> Tool {
        xaiCodeExecutionToolFactory(options)
    }

    @discardableResult
    public func viewImage(_ options: ProviderToolFactoryWithOutputSchemaOptions = .init()) -> Tool {
        xaiViewImageToolFactory(options)
    }

    @discardableResult
    public func viewXVideo(_ options: ProviderToolFactoryWithOutputSchemaOptions = .init()) -> Tool {
        xaiViewXVideoToolFactory(options)
    }

    @discardableResult
    public func fileSearch(_ args: XAIFileSearchArgs) -> Tool {
        xaiFileSearchToolFactory(args)
    }

    @discardableResult
    public func mcpServer(_ args: XAIMCPServerArgs) -> Tool {
        xaiMcpServerToolFactory(args)
    }
}

public let xaiTools = XAITools()

