import Testing
@testable import OpenAIProvider

@Suite("OpenAI custom tool")
struct OpenAICustomToolTests {
    @Test("openaiTools.customTool exposes provider id and args")
    func customToolFactoryEncodesArgs() {
        let tool = openaiTools.customTool(.init(
            name: "write_sql",
            description: "Write SQL.",
            format: .grammar(syntax: .regex, definition: "SELECT .+")
        ))

        #expect(tool.id == "openai.custom")
        #expect(tool.name == "custom")
        #expect(tool.args?["name"] == .string("write_sql"))
        #expect(tool.args?["description"] == .string("Write SQL."))
        #expect(tool.args?["format"] == .object([
            "type": .string("grammar"),
            "syntax": .string("regex"),
            "definition": .string("SELECT .+")
        ]))
    }
}
