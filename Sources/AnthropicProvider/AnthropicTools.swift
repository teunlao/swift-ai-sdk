import AISDKProviderUtils

public struct AnthropicTools: Sendable {
    public init() {}

    @discardableResult
    public func advisor20260301(
        _ args: AnthropicAdvisor20260301Options,
        callbacks: ProviderExecutedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicAdvisor20260301(args, callbacks: callbacks)
    }

    @discardableResult
    public func bash20241022(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
        anthropicBash20241022(options)
    }

    @discardableResult
    public func bash20250124(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
        anthropicBash20250124(options)
    }

    @discardableResult
    public func codeExecution20250522(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        anthropicCodeExecution20250522(options)
    }

    @discardableResult
    public func codeExecution20250825(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        anthropicCodeExecution20250825(options)
    }

    @discardableResult
    public func codeExecution20260120(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        anthropicCodeExecution20260120(options)
    }

    @discardableResult
    public func memory20250818(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
        anthropicMemory20250818(options)
    }

    @discardableResult
    public func computer20241022(
        _ args: AnthropicComputerOptions,
        options: ProviderDefinedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicComputer20241022(args, options: options)
    }

    @discardableResult
    public func computer20250124(
        _ args: AnthropicComputerOptions,
        options: ProviderDefinedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicComputer20250124(args, options: options)
    }

    @discardableResult
    public func computer20251124(
        _ args: AnthropicComputerOptions,
        options: ProviderDefinedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicComputer20251124(args, options: options)
    }

    @discardableResult
    public func computerToolset20260801(
        _ args: AnthropicComputerToolsetArgs = .init(),
        options: ProviderDefinedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicComputerToolset20260801(args, options: options)
    }

    @discardableResult
    public func textEditor20241022(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
        anthropicTextEditor20241022(options)
    }

    @discardableResult
    public func textEditor20250124(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
        anthropicTextEditor20250124(options)
    }

    @available(*, deprecated, message: "Use textEditor20250728 instead")
    @discardableResult
    public func textEditor20250429(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
        anthropicTextEditor20250429(options)
    }

    @discardableResult
    public func textEditor20250728(
        _ args: AnthropicTextEditor20250728Args = .init(),
        options: ProviderDefinedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicTextEditor20250728(args, options: options)
    }

    @discardableResult
    public func webFetch20250910(
        _ args: AnthropicWebFetchOptions = .init(),
        callbacks: ProviderExecutedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicWebFetch20250910(args, callbacks: callbacks)
    }

    @discardableResult
    public func webFetch20260209(
        _ args: AnthropicWebFetchOptions = .init(),
        callbacks: ProviderExecutedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicWebFetch20260209(args, callbacks: callbacks)
    }

    @discardableResult
    public func webFetch20260318(
        _ args: AnthropicWebFetch20260318Args = .init(),
        callbacks: ProviderExecutedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicWebFetch20260318(args, callbacks: callbacks)
    }

    @discardableResult
    public func webSearch20250305(
        _ args: AnthropicWebSearchOptions = .init(),
        callbacks: ProviderExecutedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicWebSearch20250305(args, callbacks: callbacks)
    }

    @discardableResult
    public func webSearch20260209(
        _ args: AnthropicWebSearchOptions = .init(),
        callbacks: ProviderExecutedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicWebSearch20260209(args, callbacks: callbacks)
    }

    @discardableResult
    public func webSearch20260318(
        _ args: AnthropicWebSearch20260318Args = .init(),
        callbacks: ProviderExecutedToolFactoryOptions = .init()
    ) -> Tool {
        anthropicWebSearch20260318(args, callbacks: callbacks)
    }

    @discardableResult
    public func toolSearchRegex20251119(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        anthropicToolSearchRegex20251119(options)
    }

    @discardableResult
    public func toolSearchBm2520251119(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        anthropicToolSearchBm2520251119(options)
    }
}

public let anthropicTools = AnthropicTools()
