import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GroqTools: Sendable {
    public init() {}

    @discardableResult
    public func browserSearch() -> Tool {
        groqBrowserSearchTool()
    }
}

public let groqTools = GroqTools()
