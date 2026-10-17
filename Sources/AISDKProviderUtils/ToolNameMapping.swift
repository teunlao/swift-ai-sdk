import Foundation
import AISDKProvider

public struct ToolNameMapping: Sendable {
    private var customToProvider: [Data: String]
    private var providerToCustom: [Data: String]

    public init(
        customToolNameToProviderToolName: [String: String] = [:],
        providerToolNameToCustomToolName: [String: String] = [:]
    ) {
        self.customToProvider = Dictionary(uniqueKeysWithValues: customToolNameToProviderToolName.map { (Data($0.key.utf8), $0.value) })
        self.providerToCustom = Dictionary(uniqueKeysWithValues: providerToolNameToCustomToolName.map { (Data($0.key.utf8), $0.value) })
    }

    public func toProviderToolName(_ customToolName: String) -> String {
        customToProvider[Data(customToolName.utf8)] ?? customToolName
    }

    public func toCustomToolName(_ providerToolName: String) -> String {
        providerToCustom[Data(providerToolName.utf8)] ?? providerToolName
    }

    fileprivate mutating func record(custom: String, provider: String) {
        customToProvider[Data(custom.utf8)] = provider
        providerToCustom[Data(provider.utf8)] = custom
    }
}

public func createToolNameMapping(
    tools: [LanguageModelV4Tool]? = nil,
    providerToolNames: [String: String]
) -> ToolNameMapping {
    var mapping = ToolNameMapping()
    for tool in tools ?? [] {
        guard case .provider(let tool) = tool, let name = providerToolNames[tool.id] else { continue }
        mapping.record(custom: tool.name, provider: name)
    }
    return mapping
}
