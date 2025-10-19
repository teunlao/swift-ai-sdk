import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicTools: Sendable {
    public init() {}

    @discardableResult
    public func bash20241022(_ options: AnthropicBashOptions = .init()) -> Tool {
        anthropicBash20241022(options)
    }

    @discardableResult
    public func bash20250124(_ options: AnthropicBashOptions = .init()) -> Tool {
        anthropicBash20250124(options)
    }

    @discardableResult
    public func codeExecution20250522() -> Tool {
        anthropicCodeExecution20250522()
    }

    @discardableResult
    public func computer20241022(_ options: AnthropicComputerOptions) -> Tool {
        anthropicComputer20241022(options)
    }

    @discardableResult
    public func computer20250124(_ options: AnthropicComputerOptions) -> Tool {
        anthropicComputer20250124(options)
    }

    @discardableResult
    public func textEditor20241022() -> Tool {
        anthropicTextEditor20241022()
    }

    @discardableResult
    public func textEditor20250124() -> Tool {
        anthropicTextEditor20250124()
    }

    @discardableResult
    public func textEditor20250429() -> Tool {
        anthropicTextEditor20250429()
    }

    @discardableResult
    public func textEditor20250728(_ options: AnthropicTextEditor20250728Args = .init()) -> Tool {
        anthropicTextEditor20250728(options)
    }

    @discardableResult
    public func webFetch20250910(_ options: AnthropicWebFetchOptions = .init()) -> Tool {
        anthropicWebFetch20250910(options)
    }

    @discardableResult
    public func webSearch20250305(_ options: AnthropicWebSearchOptions = .init()) -> Tool {
        anthropicWebSearch20250305(options)
    }
}

public let anthropicTools = AnthropicTools()
