import Foundation
import Testing
@testable import AISDKProvider
@testable import CohereProvider

@Suite("convertToCohereChatPrompt")
struct ConvertToCohereChatPromptTests {
    @Test("extracts documents from file parts")
    func extractsDocumentsFromFileParts() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "Analyze this file: ")),
                .file(.init(
                    data: .data(Data("This is file content".utf8)),
                    mediaType: "text/plain",
                    filename: "test.txt"
                )),
            ], providerOptions: nil),
        ]

        let result = try convertToCohereChatPrompt(prompt)

        #expect(result.messages == [
            .object([
                "role": .string("user"),
                "content": .string("Analyze this file: "),
            ]),
        ])

        #expect(result.documents == [
            .object([
                "data": .object([
                    "text": .string("This is file content"),
                    "title": .string("test.txt"),
                ]),
            ]),
        ])

        #expect(result.warnings.isEmpty)
    }

    @Test("throws for unsupported media types")
    func throwsForUnsupportedMediaTypes() {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(
                    data: .data(Data("PDF content".utf8)),
                    mediaType: "application/pdf",
                    filename: "test.pdf"
                )),
            ], providerOptions: nil),
        ]

        do {
            _ = try convertToCohereChatPrompt(prompt)
            Issue.record("Expected UnsupportedFunctionalityError")
        } catch let error as UnsupportedFunctionalityError {
            #expect(error.message.contains("Media type 'application/pdf' is not supported"))
        } catch {
            Issue.record("Expected UnsupportedFunctionalityError, got: \(error)")
        }
    }

    @Test("converts a tool call into a Cohere assistant message")
    func convertsToolCallMessage() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .text(.init(text: "Calling a tool")),
                .toolCall(.init(
                    toolCallId: "tool-call-1",
                    toolName: "tool-1",
                    input: .object(["test": .string("This is a tool message")])
                )),
            ], providerOptions: nil),
        ]

        let result = try convertToCohereChatPrompt(prompt)

        #expect(result.messages == [
            .object([
                "role": .string("assistant"),
                "tool_calls": .array([
                    .object([
                        "id": .string("tool-call-1"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("tool-1"),
                            "arguments": .string("{\"test\":\"This is a tool message\"}"),
                        ]),
                    ]),
                ]),
            ]),
        ])
        #expect(result.documents.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("converts a single tool result into a Cohere tool message")
    func convertsSingleToolResult() throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "tool-call-1",
                    toolName: "tool-1",
                    output: .json(value: .object(["test": .string("This is a tool message")]))
                )),
            ], providerOptions: nil),
        ]

        let result = try convertToCohereChatPrompt(prompt)

        #expect(result.messages == [
            .object([
                "role": .string("tool"),
                "content": .string("{\"test\":\"This is a tool message\"}"),
                "tool_call_id": .string("tool-call-1"),
            ]),
        ])
        #expect(result.documents.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("converts multiple tool results into Cohere tool messages")
    func convertsMultipleToolResults() throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "tool-call-1",
                    toolName: "tool-1",
                    output: .json(value: .object(["test": .string("This is a tool message")]))
                )),
                .toolResult(.init(
                    toolCallId: "tool-call-2",
                    toolName: "tool-2",
                    output: .json(value: .object(["something": .string("else")]))
                )),
            ], providerOptions: nil),
        ]

        let result = try convertToCohereChatPrompt(prompt)

        #expect(result.messages == [
            .object([
                "role": .string("tool"),
                "content": .string("{\"test\":\"This is a tool message\"}"),
                "tool_call_id": .string("tool-call-1"),
            ]),
            .object([
                "role": .string("tool"),
                "content": .string("{\"something\":\"else\"}"),
                "tool_call_id": .string("tool-call-2"),
            ]),
        ])
        #expect(result.documents.isEmpty)
        #expect(result.warnings.isEmpty)
    }
}

