import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Anthropic provider-defined tools collection.

 Port of `@ai-sdk/anthropic/src/anthropic-tools.ts`.
 */
public struct AnthropicTools: Sendable {
    public init() {}

    /// The bash tool enables Claude to execute shell commands in a persistent bash session,
    /// allowing system operations, script execution, and command-line automation.
    ///
    /// Image results are supported.
    ///
    /// Tool name must be `bash`.
    @discardableResult
    public func bash20241022(_ options: AnthropicBashOptions = .init()) -> Tool {
        anthropicBash20241022(options)
    }

    /// The bash tool enables Claude to execute shell commands in a persistent bash session,
    /// allowing system operations, script execution, and command-line automation.
    ///
    /// Image results are supported.
    ///
    /// Tool name must be `bash`.
    @discardableResult
    public func bash20250124(_ options: AnthropicBashOptions = .init()) -> Tool {
        anthropicBash20250124(options)
    }

    /// Claude can analyze data, create visualizations, perform complex calculations,
    /// run system commands, create and edit files, and process uploaded files directly within
    /// the API conversation.
    ///
    /// The code execution tool allows Claude to run Bash commands and manipulate files,
    /// including writing code, in a secure, sandboxed environment.
    ///
    /// Tool name must be `code_execution`.
    @discardableResult
    public func codeExecution20250522() -> Tool {
        anthropicCodeExecution20250522()
    }

    /// Claude can interact with computer environments through the computer use tool, which
    /// provides screenshot capabilities and mouse/keyboard control for autonomous desktop interaction.
    ///
    /// Image results are supported.
    ///
    /// Tool name must be `computer`.
    ///
    /// - Parameters:
    ///   - displayWidthPx: The width of the display being controlled by the model in pixels.
    ///   - displayHeightPx: The height of the display being controlled by the model in pixels.
    ///   - displayNumber: The display number to control (only relevant for X11 environments). If specified, the tool will be provided a display number in the tool definition.
    @discardableResult
    public func computer20241022(_ options: AnthropicComputerOptions) -> Tool {
        anthropicComputer20241022(options)
    }

    /// Claude can interact with computer environments through the computer use tool, which
    /// provides screenshot capabilities and mouse/keyboard control for autonomous desktop interaction.
    ///
    /// Image results are supported.
    ///
    /// Tool name must be `computer`.
    ///
    /// - Parameters:
    ///   - displayWidthPx: The width of the display being controlled by the model in pixels.
    ///   - displayHeightPx: The height of the display being controlled by the model in pixels.
    ///   - displayNumber: The display number to control (only relevant for X11 environments). If specified, the tool will be provided a display number in the tool definition.
    @discardableResult
    public func computer20250124(_ options: AnthropicComputerOptions) -> Tool {
        anthropicComputer20250124(options)
    }

    /// Claude can use an Anthropic-defined text editor tool to view and modify text files,
    /// helping you debug, fix, and improve your code or other text documents. This allows Claude
    /// to directly interact with your files, providing hands-on assistance rather than just suggesting changes.
    ///
    /// Supported models: Claude Sonnet 3.5
    ///
    /// Tool name must be `str_replace_editor`.
    @discardableResult
    public func textEditor20241022() -> Tool {
        anthropicTextEditor20241022()
    }

    /// Claude can use an Anthropic-defined text editor tool to view and modify text files,
    /// helping you debug, fix, and improve your code or other text documents. This allows Claude
    /// to directly interact with your files, providing hands-on assistance rather than just suggesting changes.
    ///
    /// Supported models: Claude Sonnet 3.7
    ///
    /// Tool name must be `str_replace_editor`.
    @discardableResult
    public func textEditor20250124() -> Tool {
        anthropicTextEditor20250124()
    }

    /// Claude can use an Anthropic-defined text editor tool to view and modify text files,
    /// helping you debug, fix, and improve your code or other text documents. This allows Claude
    /// to directly interact with your files, providing hands-on assistance rather than just suggesting changes.
    ///
    /// Note: This version does not support the "undo_edit" command.
    ///
    /// Tool name must be `str_replace_based_edit_tool`.
    ///
    /// - Warning: Deprecated. Use textEditor20250728 instead.
    @available(*, deprecated, message: "Use textEditor20250728 instead")
    @discardableResult
    public func textEditor20250429() -> Tool {
        anthropicTextEditor20250429()
    }

    /// Claude can use an Anthropic-defined text editor tool to view and modify text files,
    /// helping you debug, fix, and improve your code or other text documents. This allows Claude
    /// to directly interact with your files, providing hands-on assistance rather than just suggesting changes.
    ///
    /// Note: This version does not support the "undo_edit" command and adds optional max_characters parameter.
    ///
    /// Supported models: Claude Sonnet 4, Opus 4, and Opus 4.1
    ///
    /// Tool name must be `str_replace_based_edit_tool`.
    ///
    /// - Parameter maxCharacters: Optional maximum number of characters to view in the file
    @discardableResult
    public func textEditor20250728(_ options: AnthropicTextEditor20250728Args = .init()) -> Tool {
        anthropicTextEditor20250728(options)
    }

    /// Creates a web fetch tool that gives Claude direct access to real-time web content.
    ///
    /// Tool name must be `web_fetch`.
    ///
    /// - Parameters:
    ///   - maxUses: The max_uses parameter limits the number of web fetches performed
    ///   - allowedDomains: Only fetch from these domains
    ///   - blockedDomains: Never fetch from these domains
    ///   - citations: Unlike web search where citations are always enabled, citations are optional for web fetch. Set "citations": {"enabled": true} to enable Claude to cite specific passages from fetched documents.
    ///   - maxContentTokens: The max_content_tokens parameter limits the amount of content that will be included in the context.
    @discardableResult
    public func webFetch20250910(_ options: AnthropicWebFetchOptions = .init()) -> Tool {
        anthropicWebFetch20250910(options)
    }

    /// Creates a web search tool that gives Claude direct access to real-time web content.
    ///
    /// Tool name must be `web_search`.
    ///
    /// - Parameters:
    ///   - maxUses: Maximum number of web searches Claude can perform during the conversation.
    ///   - allowedDomains: Optional list of domains that Claude is allowed to search.
    ///   - blockedDomains: Optional list of domains that Claude should avoid when searching.
    ///   - userLocation: Optional user location information to provide geographically relevant search results.
    @discardableResult
    public func webSearch20250305(_ options: AnthropicWebSearchOptions = .init()) -> Tool {
        anthropicWebSearch20250305(options)
    }
}

/// Default Anthropic tools instance.
public let anthropicTools = AnthropicTools()
