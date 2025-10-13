import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A set of tools that can be called by the language model.

 Port of `@ai-sdk/ai/src/generate-text/tool-set.ts`.
 */
public typealias ToolSet = [String: Tool]
