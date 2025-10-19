import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleTools: Sendable {
    public init() {}

    @discardableResult
    public func googleSearch(_ args: GoogleSearchArgs = .init()) -> Tool {
        googleSearchToolFactory(args)
    }

    @discardableResult
    public func urlContext() -> Tool {
        googleURLContextTool()
    }

    @discardableResult
    public func codeExecution() -> Tool {
        googleCodeExecutionTool()
    }
}

public let googleTools = GoogleTools()
