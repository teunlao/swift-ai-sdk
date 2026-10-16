import Foundation
import Testing
import AISDKProvider
import AmazonBedrockProvider

@Suite("Bedrock tool HTTP contracts")
struct BedrockPrepareToolsTests {
    private let schema: JSONValue = .object(["type": .string("object"), "additionalProperties": .bool(false)])
    @Test("Function tool choice is serialized for Bedrock", arguments: ["auto", "required", "named", "none"])
    func choices(_ value: String) async throws {
        let server = try BedrockTestServer()
        let choice: LanguageModelV4ToolChoice = value == "auto" ? .auto : value == "required" ? .required : value == "none" ? .none : .tool(toolName: "first")
        _ = try await server.provider().chat(modelId: "meta.llama3-1-8b-instruct-v1:0").doGenerate(options: .init(prompt: [], tools: [.function(.init(name: "first", inputSchema: schema)), .function(.init(name: "second", inputSchema: schema))], toolChoice: choice))
        let body = try await server.requestBody()
        if value == "none" { #expect(body["toolConfig"] == nil); return }
        let expected: JSONValue = value == "auto" ? .object(["auto": .object([:])]) : value == "required" ? .object(["any": .object([:])]) : .object(["tool": .object(["name": .string("first")])])
        #expect(body["toolConfig"]?["toolChoice"] == expected)
        #expect(body["toolConfig"]?["tools"]?.array.count == (value == "named" ? 1 : 2))
    }

    @Test("Strict tools require closed nested object schemas")
    func strictTools() async throws {
        let server = try BedrockTestServer()
        let nested: JSONValue = .object(["type": .string("object"), "additionalProperties": .bool(false), "properties": .object(["nested": .object(["type": .string("object")])])])
        let result = try await server.provider().chat(modelId: "anthropic.claude-opus-4-6-v1").doGenerate(options: .init(prompt: [], tools: [.function(.init(name: "valid", inputSchema: schema, strict: true)), .function(.init(name: "invalid", inputSchema: nested, strict: true))]))
        let tools = try await server.requestBody()["toolConfig"]?["tools"]?.array ?? []
        #expect(tools[0]["toolSpec"]?["strict"] == .bool(true))
        #expect(tools[1]["toolSpec"]?["strict"] == nil)
        #expect(result.warnings.contains { if case .unsupported(let feature, _) = $0 { return feature == "strict" }; return false })
    }

    @Test("Opaque Anthropic family supports provider tools and disables parallel use")
    func opaqueAnthropicProfile() async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider().chat(modelId: "opaque-profile", settings: .init(modelFamily: .anthropic)).doGenerate(options: .init(prompt: [], tools: [
            .provider(.init(id: "anthropic.bash_20241022", name: "bash", args: [:])),
            .function(.init(name: "function", inputSchema: schema))
        ], toolChoice: .auto, providerOptions: ["anthropic": ["disableParallelToolUse": .bool(true)]]))
        let body = try await server.requestBody()
        #expect(body["toolConfig"]?["tools"]?.array.count == 2)
        #expect(body["additionalModelRequestFields"]?["tool_choice"]?["disable_parallel_tool_use"] == .bool(true))
        #expect(body["toolConfig"]?["toolChoice"] == nil)
    }

    @Test("New Claude models reject forced tools and strict fields")
    func forcedToolsUnsupported() async throws {
        let server = try BedrockTestServer()
        let result = try await server.provider().chat(modelId: "anthropic.claude-sonnet-5-5").doGenerate(options: .init(prompt: [], tools: [.function(.init(name: "first", inputSchema: schema, strict: true)), .function(.init(name: "second", inputSchema: schema))], toolChoice: .tool(toolName: "first")))
        let body = try await server.requestBody()
        #expect(body["toolConfig"]?["toolChoice"] == .object(["auto": .object([:])]))
        #expect(body["toolConfig"]?["tools"]?.array.count == 1)
        #expect(body["toolConfig"]?["tools"]?.array.first?["toolSpec"]?["strict"] == nil)
        #expect(result.warnings.contains { if case .unsupported(let feature, _) = $0 { return feature == "toolChoice" }; return false })
    }

    @Test("Unsupported web tools are excluded from Converse requests")
    func webToolsUnsupported() async throws {
        let server = try BedrockTestServer()
        let result = try await server.provider().chat(modelId: "anthropic.claude-opus-4-6-v1").doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: "anthropic.web_search_20260318", name: "web_search", args: [:]))]))
        #expect(try await server.requestBody()["toolConfig"] == nil)
        #expect(result.warnings.count == 1)
        guard case .unsupported(let feature, _) = result.warnings.first else { Issue.record("Expected unsupported tool warning"); return }
        #expect(feature == "web_search_20260318 tool")
    }
}
