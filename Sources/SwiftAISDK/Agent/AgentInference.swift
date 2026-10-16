import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Port of `InferAgentTools`. Swift tool sets are dynamically typed, so this is `ToolSet`.
public typealias InferAgentTools<AgentType> = ToolSet

/// Port of `InferAgentUIMessage`.
public typealias InferAgentUIMessage<AgentType> = UIMessage

@available(*, deprecated, renamed: "InferAgentUIMessage")
public typealias Experimental_InferAgentUIMessage<AgentType> = InferAgentUIMessage<AgentType>
