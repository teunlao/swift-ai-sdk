import Foundation
import AISDKProvider

/// Maps between custom tool names (client) and provider tool names (OpenAI).
///
/// Port of `@ai-sdk/provider-utils/src/create-tool-name-mapping.ts`.
struct OpenAIToolNameMapping: Sendable {
    private let customToolNameToProviderToolName: [String: String]
    private let providerToolNameToCustomToolName: [String: String]

    init(
        customToolNameToProviderToolName: [String: String] = [:],
        providerToolNameToCustomToolName: [String: String] = [:]
    ) {
        self.customToolNameToProviderToolName = customToolNameToProviderToolName
        self.providerToolNameToCustomToolName = providerToolNameToCustomToolName
    }

    static func create(
        tools: [LanguageModelV3Tool]?,
        providerToolNames: [String: String]
    ) -> OpenAIToolNameMapping {
        var customToProvider: [String: String] = [:]
        var providerToCustom: [String: String] = [:]

        for tool in tools ?? [] {
            guard case .provider(let providerTool) = tool else { continue }
            guard let providerToolName = providerToolNames[providerTool.id] else { continue }

            customToProvider[providerTool.name] = providerToolName
            providerToCustom[providerToolName] = providerTool.name
        }

        return OpenAIToolNameMapping(
            customToolNameToProviderToolName: customToProvider,
            providerToolNameToCustomToolName: providerToCustom
        )
    }

    func toProviderToolName(_ customToolName: String) -> String {
        customToolNameToProviderToolName[customToolName] ?? customToolName
    }

    func toCustomToolName(_ providerToolName: String) -> String {
        providerToolNameToCustomToolName[providerToolName] ?? providerToolName
    }
}
