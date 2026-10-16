import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google prompt wire format")
struct ConvertToGoogleMessagesTests {
    @Test("replays signatures, references, reasoning files, and multimodal tool results")
    func replayPrompt() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        let call = LanguageModelV4ToolCallPart(toolCallId: "call-1", toolName: "lookup", input: .object([:]), providerOptions: ["googleVertex": ["thoughtSignature": .string("signature")]])
        let prompt: LanguageModelV4Prompt = [
            .system(content: "system", providerOptions: nil),
            .user(content: [.file(.init(data: .reference(["google": "https://generativelanguage.googleapis.com/v1beta/files/id"]), mediaType: "application/pdf")), .file(.init(data: .text("document"), mediaType: "text/*"))], providerOptions: nil),
            .assistant(content: [.reasoningFile(.init(data: .base64("AQID"), mediaType: "image/png", providerOptions: ["google": ["thoughtSignature": .string("reason")]])), .toolCall(call), .toolCall(.init(toolCallId: "call-2", toolName: "other", input: .object([:])))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call-1", toolName: "lookup", output: .content(value: [.text(text: "found", providerOptions: nil), .file(data: .base64("AQID"), mediaType: "image/png", filename: nil, providerOptions: nil)])))], providerOptions: nil)
        ]
        _ = try await model.doGenerate(options: .init(prompt: prompt))
        let request = try #require(await transport.captured().first)
        let contents = array(try googleBody(request)["contents"])
        let user = array(object(contents[0])["parts"])
        #expect(object(object(user[0])["fileData"])["fileUri"] == .string("https://generativelanguage.googleapis.com/v1beta/files/id"))
        #expect(object(object(user[1])["inlineData"])["mimeType"] == .string("text/plain"))
        let assistant = array(object(contents[1])["parts"])
        #expect(object(assistant[0])["thought"] == .bool(true))
        #expect(object(assistant[1])["thoughtSignature"] == .string("signature"))
        #expect(object(assistant[2])["thoughtSignature"] == nil)
        let response = object(object(array(object(contents[2])["parts"])[0])["functionResponse"])
        #expect(response["id"] == .string("call-1"))
        #expect(object(response["response"])["content"] == .string("found"))
        #expect(object(object(array(response["parts"]).first)["inlineData"])["data"] == .string("AQID"))
    }

    @Test("Gemini 3 injects one sentinel when signatures are missing")
    func missingSignature() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let model = await transport.provider().chat(modelId: "gemini-future")
        let result = try await model.doGenerate(options: .init(prompt: [.assistant(content: [.toolCall(.init(toolCallId: "call", toolName: "lookup", input: .object([:])))], providerOptions: nil)]))
        let request = try #require(await transport.captured().first)
        let part = object(array(object(array(try googleBody(request)["contents"]).first)["parts"]).first)
        #expect(part["thoughtSignature"] == .string("skip_thought_signature_validator"))
        #expect(result.warnings.count == 1)
    }

    @Test("Gemma prepends system text only when the first content turn is user")
    func gemmaSystem() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json")), .init(try googleFixture("text.json"))])
        let model = await transport.provider().chat(modelId: "gemma-3-27b-it")
        let user = try await model.doGenerate(options: .init(prompt: [.system(content: "system", providerOptions: nil)] + googlePrompt))
        let assistant = try await model.doGenerate(options: .init(prompt: [.system(content: "system", providerOptions: nil), .assistant(content: [.text(.init(text: "answer"))], providerOptions: nil)]))
        #expect(user.warnings.isEmpty && assistant.warnings.isEmpty)
        let requests = await transport.captured()
        let first = try googleBody(requests[0])
        let second = try googleBody(requests[1])
        #expect(object(array(object(array(first["contents"]).first)["parts"]).first)["text"] == .string("system\n\n"))
        #expect(second["systemInstruction"] == nil)
        #expect(object(array(object(array(second["contents"]).first)["parts"]).first)["text"] == .string("answer"))
    }

    @Test("system messages after content are rejected before transport")
    func lateSystem() async throws {
        let model = createGoogle(settings: .init(apiKey: "key")).chat(modelId: "gemini-3.8-flash")
        await #expect(throws: UnsupportedFunctionalityError.self) { try await model.doGenerate(options: .init(prompt: googlePrompt + [.system(content: "late", providerOptions: nil)])) }
    }
}
