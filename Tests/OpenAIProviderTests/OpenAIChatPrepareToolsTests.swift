import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

func chatExchange(
    options: LanguageModelV4CallOptions,
    modelId: String = "gpt-4o-mini"
) async throws -> (body: [String: JSONValue], result: LanguageModelV4GenerateResult) {
    actor Capture {
        var body: Data?
        func store(_ data: Data?) { body = data }
        func value() -> Data? { body }
    }
    let capture = Capture()
    let model = OpenAIChatLanguageModel(modelId: .init(rawValue: modelId), config: .init(
        provider: "custom.chat",
        url: { _ in "https://example.com/chat/completions" },
        fetch: { request in
            await capture.store(request.httpBody)
            return FetchResponse(
                body: .data(Data(#"{"choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#.utf8)),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }
    ))
    let result = try await model.doGenerate(options: options)
    let data = try #require(await capture.value())
    return (try JSONDecoder().decode([String: JSONValue].self, from: data), result)
}

@Suite("OpenAI Chat tools")
struct OpenAIChatPrepareToolsTests {
    @Test("function tools and choices are serialized at the HTTP boundary", arguments: ["auto", "none", "required", "lookup"])
    func toolChoices(choice: String) async throws {
        let toolChoice: LanguageModelV4ToolChoice
        switch choice {
        case "auto": toolChoice = .auto
        case "none": toolChoice = .none
        case "required": toolChoice = .required
        default: toolChoice = .tool(toolName: choice)
        }
        let exchange = try await chatExchange(options: .init(
            prompt: [],
            tools: [.function(.init(name: "lookup", inputSchema: .object(["type": .string("object")]), description: "Lookup", strict: true))],
            toolChoice: toolChoice
        ))
        #expect(exchange.body["tools"] == .array([.object([
            "type": .string("function"), "function": .object([
                "name": .string("lookup"), "parameters": .object(["type": .string("object")]),
                "description": .string("Lookup"), "strict": .bool(true)
            ])
        ])]))
        let expected: JSONValue = choice == "lookup"
            ? .object(["type": .string("function"), "function": .object(["name": .string("lookup")])])
            : .string(choice)
        #expect(exchange.body["tool_choice"] == expected)
    }

    @Test("empty tools omit tool choice and provider tools emit a typed warning")
    func emptyAndProviderTools() async throws {
        let empty = try await chatExchange(options: .init(prompt: [], tools: [], toolChoice: .required))
        #expect(empty.body["tools"] == nil)
        #expect(empty.body["tool_choice"] == nil)
        let provider = try await chatExchange(options: .init(prompt: [], tools: [.provider(.init(id: "openai.unsupported", name: "unsupported", args: [:]))]))
        #expect(provider.body["tools"] == .array([]))
        #expect(provider.result.warnings == [.unsupported(feature: "tool type: provider", details: nil)])
    }

    @Test("schema normalization preserves character classes and removes actual lookaround", arguments: ["(?=\u{301}x)", "[\u{301}(?=]", "(?<=x)y"])
    func schemaPatterns(pattern: String) async throws {
        let schema: JSONValue = .object(["type": .string("string"), "pattern": .string(pattern)])
        let exchange = try await chatExchange(options: .init(
            prompt: [], responseFormat: .json(schema: schema, name: nil, description: nil),
            tools: [.function(.init(name: "lookup", inputSchema: schema))]
        ))
        let removes = pattern != "[\u{301}(?=]"
        let normalized: JSONValue = removes ? .object(["type": .string("string")]) : schema
        #expect(exchange.body["response_format"] == .object([
            "type": .string("json_schema"), "json_schema": .object(["schema": normalized, "strict": .bool(true), "name": .string("response")])
        ]))
        #expect(exchange.body["tools"] == .array([.object([
            "type": .string("function"), "function": .object(["name": .string("lookup"), "parameters": normalized])
        ])]))
        #expect(exchange.result.warnings.count == (removes ? 2 : 0))
    }

    @Test("local root references resolve combining names but preserve empty and newline names", arguments: ["\u{301}entry", "", "line\nbreak"])
    func schemaReferences(name: String) async throws {
        let definition: JSONValue = .object(["type": .string("object"), "properties": .object([:])])
        let schema: JSONValue = .object([
            "allOf": .array([.object(["$ref": .string("#/$defs/" + name)])]), "$defs": .object([name: definition])
        ])
        let exchange = try await chatExchange(options: .init(prompt: [], responseFormat: .json(schema: schema, name: nil, description: nil)))
        let expected: JSONValue = name == "\u{301}entry"
            ? .object(["type": .string("object"), "properties": .object([:]), "$defs": .object([name: definition])])
            : schema
        #expect(exchange.body["response_format"] == .object([
            "type": .string("json_schema"), "json_schema": .object(["schema": expected, "strict": .bool(true), "name": .string("response")])
        ]))
    }
}
