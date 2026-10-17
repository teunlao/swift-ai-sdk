import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("OpenAI tool validation contracts")
struct OpenAIToolValidationTests {
    @Test("Tool output validation projects known fields while retaining nullable and arbitrary data")
    func outputProjection() async throws {
        let cases: [(Tool, JSONValue, JSONValue)] = [
            (openaiTools.codeInterpreter(),
             .object(["outputs": .array([.object(["type": .string("logs"), "logs": .string("ok"), "url": .string("ignored")])]), "extra": .bool(true)]),
             .object(["outputs": .array([.object(["type": .string("logs"), "logs": .string("ok")])])])),
            (openaiTools.webSearch(),
             .object(["action": .object(["type": .string("findInPage"), "url": .null, "pattern": .null, "extra": .bool(true)]), "extra": .bool(true)]),
             .object(["action": .object(["type": .string("findInPage"), "url": .null, "pattern": .null])])),
            (openaiTools.mcp(.init(serverLabel: "docs", serverUrl: "")),
             .object(["type": .string("call"), "serverLabel": .string("docs"), "name": .string("read"), "arguments": .string("{}"), "output": .null, "error": .array([.number(1)])]),
             .object(["type": .string("call"), "serverLabel": .string("docs"), "name": .string("read"), "arguments": .string("{}"), "output": .null, "error": .array([.number(1)])])),
            (openaiTools.toolSearch(),
             .object(["tools": .array([.object(["future": .object(["nested": .null])])]), "extra": .bool(true)]),
             .object(["tools": .array([.object(["future": .object(["nested": .null])])])]))
        ]
        for (tool, value, expected) in cases {
            let schema = try #require(tool.outputSchema)
            let parsed = try await validateTypes(ValidateTypesOptions(value: value, schema: schema))
            #expect(parsed == expected)
        }
    }

    @Test("Provider tool numeric outputs reject non-finite JSON numbers")
    func finiteNumericOutput() async throws {
        let schema = try #require(openaiTools.fileSearch(.init(vectorStoreIds: [])).outputSchema)
        await #expect(throws: TypeValidationError.self) {
            try await validateTypes(ValidateTypesOptions(value: JSONValue.object([
                "queries": .array([]), "results": .array([.object([
                    "attributes": .object([:]), "fileId": .string("file"), "filename": .string("file"),
                    "score": .number(.infinity), "text": .string("content")
                ])])
            ]), schema: schema))
        }
    }

    @Test("Shell limits require representable integer inputs", arguments: [0.5, 1e20])
    func integerShellLimits(_ limit: Double) async throws {
        await #expect(throws: TypeValidationError.self) {
            _ = try await validateTypes(ValidateTypesOptions(value: JSONValue.object([
                "action": .object(["commands": .array([.string("pwd")]), "maxOutputLength": .number(limit)])
            ]), schema: openaiTools.shell().inputSchema))
        }
    }

    @Test("Tool validation rejects missing operation fields and explicit null optional fields")
    func invalidInputs() async throws {
        await #expect(throws: TypeValidationError.self) {
            try await validateTypes(ValidateTypesOptions(value: JSONValue.object([
                "callId": .string("call"), "operation": .object(["type": .string("update_file"), "path": .string("file")])
            ]), schema: openaiTools.applyPatch().inputSchema))
        }
        await #expect(throws: TypeValidationError.self) {
            try await validateTypes(ValidateTypesOptions(value: JSONValue.object([
                "action": .object(["type": .string("exec"), "command": .array([]), "timeoutMs": .null])
            ]), schema: openaiTools.localShell().inputSchema))
        }
    }
}
