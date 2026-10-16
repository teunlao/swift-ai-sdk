import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Port of `InferAgentTools`. Swift tool sets are dynamically typed, so this is `ToolSet`.
public typealias InferAgentTools<AgentType> = ToolSet

/// Port of `InferAgentUIMessage`.
public typealias InferAgentUIMessage<AgentType> = UIMessage
