import Testing
@testable import AISDKProvider
import Foundation

@Suite("LanguageModelV2 CallWarning")
struct LanguageModelV2CallWarningTests {

    @Test("CallWarning: unsupportedSetting round-trip with details")
    func unsupported_setting_with_details() throws {
        let w = LanguageModelV2CallWarning.unsupportedSetting(setting: "temperature", details: "clamped to [0,1]")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV2CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: unsupportedSetting round-trip without details")
    func unsupported_setting_without_details() throws {
        let w = LanguageModelV2CallWarning.unsupportedSetting(setting: "topK", details: nil)
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV2CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: unsupportedTool with FunctionTool")
    func unsupported_tool_function() throws {
        let tool = LanguageModelV2Tool.function(.init(name: "search", inputSchema: ["type": .string("object")], description: nil))
        let w = LanguageModelV2CallWarning.unsupportedTool(tool: tool, details: "provider-side only")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV2CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: unsupportedTool with ProviderDefinedTool")
    func unsupported_tool_provider_defined() throws {
        let tool = LanguageModelV2Tool.providerDefined(.init(id: "code-exec", name: "Code Execution", args: [:]))
        let w = LanguageModelV2CallWarning.unsupportedTool(tool: tool, details: nil)
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV2CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: other message")
    func other_message() throws {
        let w = LanguageModelV2CallWarning.other(message: "something else")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV2CallWarning.self, from: data)
        #expect(back == w)
    }
}

