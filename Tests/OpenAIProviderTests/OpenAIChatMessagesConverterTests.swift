import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("OpenAI Chat messages")
struct OpenAIChatMessagesConverterTests {
    @Test("system modes and single text messages reach the HTTP request", arguments: ["system", "developer", "remove"])
    func systemModes(mode: String) async throws {
        let exchange = try await chatExchange(options: .init(
            prompt: [.system(content: "instructions", providerOptions: nil), .user(content: [.text(.init(text: "hello"))], providerOptions: nil)],
            providerOptions: ["openai": ["systemMessageMode": .string(mode)]]
        ))
        let user: JSONValue = .object(["role": .string("user"), "content": .string("hello")])
        let expected: [JSONValue] = mode == "remove" ? [user] : [.object(["role": .string(mode), "content": .string("instructions")]), user]
        #expect(exchange.body["messages"] == .array(expected))
        #expect(exchange.result.warnings.count == (mode == "remove" ? 1 : 0))
    }

    @Test("inline media resolves MIME types and serializes OpenAI content", arguments: ["image", "audio/wav", "audio/mpeg", "audio/mp3", "application"])
    func inlineMedia(mediaType: String) async throws {
        let data = mediaType == "image" ? Data([0xff, 0xd8, 0xff, 0xe0]) : (mediaType == "application" ? Data("%PDF-1.0".utf8) : Data([1, 2, 3]))
        let exchange = try await chatExchange(options: .init(prompt: [
            .user(content: [.file(.init(data: .data(data), mediaType: mediaType))], providerOptions: nil)
        ]))
        let expected: JSONValue
        if mediaType == "image" {
            expected = .object(["type": .string("image_url"), "image_url": .object(["url": .string("data:image/jpeg;base64," + data.base64EncodedString())])])
        } else if mediaType == "application" {
            expected = .object(["type": .string("file"), "file": .object(["filename": .string("part-0.pdf"), "file_data": .string("data:application/pdf;base64," + data.base64EncodedString())])])
        } else {
            expected = .object(["type": .string("input_audio"), "input_audio": .object(["data": .string(data.base64EncodedString()), "format": .string(mediaType == "audio/wav" ? "wav" : "mp3")])])
        }
        #expect(exchange.body["messages"] == .array([.object(["role": .string("user"), "content": .array([expected])])]))
    }

    @Test("file references use the OpenAI namespace while image URLs keep detail")
    func referencesAndURLs() async throws {
        let exchange = try await chatExchange(options: .init(prompt: [.user(content: [
            .file(.init(data: .reference(["openai": "file-pdf", "custom": "wrong-id"]), mediaType: "application/pdf")),
            .file(.init(data: .url(URL(string: "https://example.com/image.jpg")!), mediaType: "image/jpeg", providerOptions: ["openai": ["imageDetail": .string("high")]])),
            .file(.init(data: .base64("AQID"), mediaType: "application/pdf", filename: "report.pdf"))
        ], providerOptions: nil)]))
        #expect(exchange.body["messages"] == .array([.object(["role": .string("user"), "content": .array([
            .object(["type": .string("file"), "file": .object(["file_id": .string("file-pdf")])]),
            .object(["type": .string("image_url"), "image_url": .object(["url": .string("https://example.com/image.jpg"), "detail": .string("high")])]),
            .object(["type": .string("file"), "file": .object(["filename": .string("report.pdf"), "file_data": .string("data:application/pdf;base64,AQID")])])
        ])])]))
        do {
            _ = try await chatExchange(options: .init(prompt: [.user(content: [.file(.init(data: .reference(["custom": "wrong-id"]), mediaType: "application/pdf"))], providerOptions: nil)]))
            Issue.record("Expected a missing provider reference")
        } catch let error as NoSuchProviderReferenceError {
            #expect(error.provider == "openai")
        }
    }

    @Test("unsupported file representations fail at the public operation", arguments: ["audio-url", "pdf-url", "inline-text", "media-type"])
    func unsupportedFiles(variant: String) async throws {
        let file: LanguageModelV4FilePart
        switch variant {
        case "audio-url": file = .init(data: .url(URL(string: "https://example.com/audio.wav")!), mediaType: "audio/wav")
        case "pdf-url": file = .init(data: .url(URL(string: "https://example.com/document.pdf")!), mediaType: "application/pdf")
        case "inline-text": file = .init(data: .text("hello"), mediaType: "text/plain")
        default: file = .init(data: .base64("AQID"), mediaType: "text/plain")
        }
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await chatExchange(options: .init(prompt: [.user(content: [.file(file)], providerOptions: nil)]))
        }
    }

    @Test("assistant tool arguments coerce non-objects while JSON results preserve fragments", arguments: [JSONValue.string("4"), .number(4), .null, .array([.number(4)])])
    func toolJSON(input: JSONValue) async throws {
        let exchange = try await chatExchange(options: .init(prompt: [
            .assistant(content: [.toolCall(.init(toolCallId: "call-1", toolName: "calculate", input: input))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call-1", toolName: "calculate", output: .json(value: input, providerOptions: nil)))], providerOptions: nil)
        ]))
        let encoded = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        #expect(exchange.body["messages"] == .array([
            .object(["role": .string("assistant"), "content": .null, "tool_calls": .array([.object(["id": .string("call-1"), "type": .string("function"), "function": .object(["name": .string("calculate"), "arguments": .string("{}")])])])]),
            .object(["role": .string("tool"), "tool_call_id": .string("call-1"), "content": .string(encoded)])
        ]))
    }

    @Test("tool errors are wrapped and execution denial uses a usable content value")
    func toolErrors() async throws {
        let outputs: [LanguageModelV4ToolResultOutput] = [
            .errorText(value: "failed", providerOptions: nil), .errorJson(value: .object(["code": .number(7)]), providerOptions: nil),
            .executionDenied(reason: nil, providerOptions: nil), .text(value: "plain", providerOptions: nil)
        ]
        let exchange = try await chatExchange(options: .init(prompt: [.tool(content: outputs.enumerated().map { index, output in
            .toolResult(.init(toolCallId: String(index), toolName: "lookup", output: output))
        }, providerOptions: nil)]))
        let values = [#"{"error":"failed"}"#, #"{"error":{"code":7}}"#, "Tool call execution denied.", "plain"]
        #expect(exchange.body["messages"] == .array(values.enumerated().map { index, value in
            .object(["role": .string("tool"), "tool_call_id": .string(String(index)), "content": .string(value)])
        }))
    }

    @Test("tool content serializes native file data in the public wire representation")
    func toolContent() async throws {
        let exchange = try await chatExchange(options: .init(prompt: [
            .assistant(content: [.toolCall(.init(toolCallId: "call", toolName: "lookup", input: .object(["query": .string("swift")])) )], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "lookup", output: .content(value: [
                .text(text: "document", providerOptions: nil),
                .file(data: .reference(["openai": "file-doc"]), mediaType: "application/pdf", filename: "report.pdf", providerOptions: nil)
            ])))], providerOptions: nil)
        ]))
        guard case .array(let messages)? = exchange.body["messages"],
              case .object(let assistant) = messages[0],
              case .object(let tool) = messages[1], case .string(let content)? = tool["content"] else { Issue.record("Missing messages"); return }
        #expect(assistant["tool_calls"] == .array([.object([
            "id": .string("call"), "type": .string("function"), "function": .object(["name": .string("lookup"), "arguments": .string(#"{"query":"swift"}"#)])
        ])]))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(content.utf8))
        #expect(decoded == .array([
            .object(["type": .string("text"), "text": .string("document")]),
            .object(["type": .string("file"), "data": .object(["type": .string("reference"), "reference": .object(["openai": .string("file-doc")])]), "mediaType": .string("application/pdf"), "filename": .string("report.pdf")])
        ]))
    }

    @Test("cache breakpoints survive system user assistant and tool content")
    func cacheBreakpoints() async throws {
        let breakpoint: JSONValue = .object(["mode": .string("explicit")])
        let options: SharedV4ProviderOptions = ["openai": ["promptCacheBreakpoint": breakpoint]]
        let exchange = try await chatExchange(options: .init(prompt: [
            .system(content: "instructions", providerOptions: options),
            .user(content: [.text(.init(text: "hello", providerOptions: options))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "answer", providerOptions: options))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "lookup", output: .text(value: "result", providerOptions: options)))], providerOptions: nil)
        ]))
        let messages = ["system", "user", "assistant", "tool"].enumerated().map { index, role -> JSONValue in
            var message: [String: JSONValue] = ["role": .string(role), "content": .array([.object([
                "type": .string("text"), "text": .string(["instructions", "hello", "answer", "result"][index]), "prompt_cache_breakpoint": breakpoint
            ])])]
            if role == "tool" { message["tool_call_id"] = .string("call") }
            return .object(message)
        }
        #expect(exchange.body["messages"] == .array(messages))
    }
}
