import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Callback invoked when an agent step finishes (mirrors `AgentOnStepFinishCallback`).
public typealias AgentOnStepFinishCallback = GenerateTextOnStepFinishCallback

/// Callback invoked when an agent completes all steps (mirrors `AgentOnFinishCallback`).
public typealias AgentOnFinishCallback = GenerateTextOnFinishCallback

/// Helper alias mirroring the upstream `InferAgentTools` utility.
///
/// Swift currently keeps tool sets dynamically typed (`ToolSet`), therefore the alias simply
/// returns `ToolSet` to preserve API familiarity.
public typealias InferAgentTools<AgentType> = ToolSet

/// Helper alias mirroring the upstream `InferAgentUIMessage` utility.
public typealias InferAgentUIMessage<AgentType> = UIMessage

// MARK: - Deprecated aliases

@available(*, deprecated, renamed: "InferAgentUIMessage")
public typealias Experimental_InferAgentUIMessage<AgentType> = InferAgentUIMessage<AgentType>
