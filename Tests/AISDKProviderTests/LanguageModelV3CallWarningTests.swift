import Testing
@testable import AISDKProvider
import Foundation

@Suite("LanguageModelV3 CallWarning")
struct LanguageModelV3CallWarningTests {

    @Test("CallWarning: unsupportedSetting round-trip with details")
    func v3_unsupported_setting_with_details() throws {
        let w = LanguageModelV3CallWarning.unsupportedSetting(setting: "temperature", details: "clamped to [0,1]")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV3CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: unsupportedSetting round-trip without details")
    func v3_unsupported_setting_without_details() throws {
        let w = LanguageModelV3CallWarning.unsupportedSetting(setting: "topK", details: nil)
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV3CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: unsupportedTool with FunctionTool")
    func v3_unsupported_tool_function() throws {
        let tool = LanguageModelV3Tool.function(.init(name: "search", inputSchema: ["type": .string("object")], description: nil))
        let w = LanguageModelV3CallWarning.unsupportedTool(tool: tool, details: "provider-side only")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV3CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: unsupportedTool with ProviderDefinedTool")
    func v3_unsupported_tool_provider_defined() throws {
        let tool = LanguageModelV3Tool.providerDefined(.init(id: "code-exec", name: "Code Execution", args: [:]))
        let w = LanguageModelV3CallWarning.unsupportedTool(tool: tool, details: nil)
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV3CallWarning.self, from: data)
        #expect(back == w)
    }

    @Test("CallWarning: other message")
    func v3_other_message() throws {
        let w = LanguageModelV3CallWarning.other(message: "something else")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(LanguageModelV3CallWarning.self, from: data)
        #expect(back == w)
    }
}

