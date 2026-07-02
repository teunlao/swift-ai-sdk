import Foundation
import AISDKProvider

/// Maps between client-facing custom tool names and provider tool names.
public struct ToolNameMapping: Sendable {
    private let customToolNameToProviderToolName: [String: String]
    private let providerToolNameToCustomToolName: [String: String]

    public init(
        customToolNameToProviderToolName: [String: String] = [:],
        providerToolNameToCustomToolName: [String: String] = [:]
    ) {
        self.customToolNameToProviderToolName = customToolNameToProviderToolName
        self.providerToolNameToCustomToolName = providerToolNameToCustomToolName
    }

    public func toProviderToolName(_ customToolName: String) -> String {
        customToolNameToProviderToolName[customToolName] ?? customToolName
    }

    public func toCustomToolName(_ providerToolName: String) -> String {
        providerToolNameToCustomToolName[providerToolName] ?? providerToolName
    }
}

public func createToolNameMapping(
    tools: [LanguageModelV4Tool]? = nil,
    providerToolNames: [String: String]
) -> ToolNameMapping {
    var customToProvider: [String: String] = [:]
    var providerToCustom: [String: String] = [:]

    for tool in tools ?? [] {
        guard case .provider(let providerTool) = tool,
              let providerToolName = providerToolNames[providerTool.id] else {
            continue
        }

        customToProvider[providerTool.name] = providerToolName
        providerToCustom[providerToolName] = providerTool.name
    }

    return ToolNameMapping(
        customToolNameToProviderToolName: customToProvider,
        providerToolNameToCustomToolName: providerToCustom
    )
}
