import AISDKProviderUtils

public struct GroqTools: Sendable {
    public init() {}

    public func browserSearch(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        groqBrowserSearchFactory(options)
    }
}
