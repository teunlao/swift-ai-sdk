import Testing
@testable import AISDKProvider
import Foundation

@Suite("LanguageModelV3 CallOptions")
struct LanguageModelV3CallOptionsTests {

    @Test("CallOptions: minimal configuration")
    func v3_minimal() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "you are helpful", providerOptions: nil)
        ]

        let opts = LanguageModelV3CallOptions(prompt: prompt)
        #expect(opts.prompt.count == 1)
        #expect(opts.maxOutputTokens == nil)
        #expect(opts.temperature == nil)
        #expect(opts.stopSequences == nil)
        #expect(opts.topP == nil)
        #expect(opts.topK == nil)
        #expect(opts.presencePenalty == nil)
        #expect(opts.frequencyPenalty == nil)
        #expect(opts.responseFormat == nil)
        #expect(opts.seed == nil)
        #expect(opts.tools == nil)
        #expect(opts.toolChoice == nil)
        #expect(opts.includeRawChunks == nil)
        #expect(opts.abortSignal == nil)
        #expect(opts.headers == nil)
        #expect(opts.providerOptions == nil)
    }

    @Test("CallOptions: full configuration")
    func v3_full() throws {
        // Prompt with user text + file, assistant with tool-call, tool message with result
        let userParts: [LanguageModelV3UserMessagePart] = [
            .text(.init(text: "Hello")),
            .file(.init(data: .url(URL(string: "https://example.com/a.png")!), mediaType: "image/png", filename: "a.png"))
        ]
        let toolCallPart = LanguageModelV3MessagePart.toolCall(.init(
            toolCallId: "c1",
            toolName: "search",
            input: ["q": .string("swift")],
            providerExecuted: true
        ))
        let prompt: LanguageModelV3Prompt = [
            .system(content: "you are helpful", providerOptions: ["x": ["y": .string("z")]]),
            .user(content: userParts, providerOptions: nil),
            .assistant(content: [.text(.init(text: "Working...")), toolCallPart], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "c1", toolName: "noop", output: .text(value: "Done")))], providerOptions: nil)
        ]

        let functionTool = LanguageModelV3Tool.function(.init(name: "search", inputSchema: ["type": .string("object")], description: "find"))
        let providerTool = LanguageModelV3Tool.provider(.init(id: "code-exec", name: "Code Execution", args: [:]))

        let schema: JSONValue = ["type": .string("object")]
        let opts = LanguageModelV3CallOptions(
            prompt: prompt,
            maxOutputTokens: 512,
            temperature: 0.2,
            stopSequences: ["\n\n"],
            topP: 0.95,
            topK: 40,
            presencePenalty: 0.1,
            frequencyPenalty: 0.3,
            responseFormat: .json(schema: schema, name: "MySchema", description: "desc"),
            seed: 42,
            tools: [functionTool, providerTool],
            toolChoice: .required,
            includeRawChunks: true,
            abortSignal: { true },
            headers: ["x-api": "1"],
            providerOptions: ["provider": ["opt": .bool(true)]]
        )

        #expect(opts.prompt.count == 4)
        #expect(opts.maxOutputTokens == 512)
        #expect(opts.temperature == 0.2)
        #expect(opts.stopSequences == ["\n\n"])
        #expect(opts.topP == 0.95)
        #expect(opts.topK == 40)
        #expect(opts.presencePenalty == 0.1)
        #expect(opts.frequencyPenalty == 0.3)
        if case .json(let sch, let name, let descr)? = opts.responseFormat {
            #expect(sch != nil)
            #expect(name == "MySchema")
            #expect(descr == "desc")
        } else { #expect(Bool(false)) }
        #expect(opts.seed == 42)
        #expect(opts.tools?.count == 2)
        #expect(opts.includeRawChunks == true)
        #expect(opts.abortSignal?() == true)
        #expect(opts.headers?["x-api"] == "1")
        #expect(opts.providerOptions?["provider"]?["opt"] == .bool(true))
    }
}
