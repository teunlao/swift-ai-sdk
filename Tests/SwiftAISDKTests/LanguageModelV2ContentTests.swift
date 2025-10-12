import Foundation
import Testing
@testable import SwiftAISDK

/**
 * Tests for LanguageModelV2 Content types
 *
 * Tests Text, Reasoning, File, Source, and Content enum
 */

@Suite("LanguageModelV2 Content Types")
struct LanguageModelV2ContentTests {

    // MARK: - Text

    @Test("Text: encode/decode round-trip")
    func text_roundTrip() throws {
        let pm: SharedV2ProviderMetadata = ["provider": ["key": .string("value")]]
        let text = LanguageModelV2Text(text: "Hello World", providerMetadata: pm)

        let data = try JSONEncoder().encode(text)
        let decoded = try JSONDecoder().decode(LanguageModelV2Text.self, from: data)

        #expect(decoded.text == "Hello World")
        #expect(decoded.providerMetadata == pm)
    }

    @Test("Text: encode without providerMetadata")
    func text_noMetadata() throws {
        let text = LanguageModelV2Text(text: "Plain text", providerMetadata: nil)

        let data = try JSONEncoder().encode(text)
        let json = String(data: data, encoding: .utf8)!

        #expect(!json.contains("providerMetadata"))

        let decoded = try JSONDecoder().decode(LanguageModelV2Text.self, from: data)
        #expect(decoded.text == "Plain text")
        #expect(decoded.providerMetadata == nil)
    }

    // MARK: - Reasoning

    @Test("Reasoning: encode/decode round-trip")
    func reasoning_roundTrip() throws {
        let pm: SharedV2ProviderMetadata = ["openai": ["tokens": .number(42)]]
        let reasoning = LanguageModelV2Reasoning(text: "Let me think...", providerMetadata: pm)

        let data = try JSONEncoder().encode(reasoning)
        let decoded = try JSONDecoder().decode(LanguageModelV2Reasoning.self, from: data)

        #expect(decoded.text == "Let me think...")
        #expect(decoded.providerMetadata == pm)
    }

    // MARK: - File

    @Test("File: encode/decode with base64 data")
    func file_base64Data() throws {
        let file = LanguageModelV2File(
            mediaType: "image/png",
            data: .base64("QUJDREVG")
        )

        let encoded = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(LanguageModelV2File.self, from: encoded)

        #expect(decoded.data == .base64("QUJDREVG"))
        #expect(decoded.mediaType == "image/png")
    }

    @Test("File: encode with binary data")
    func file_binaryData() throws {
        let binaryData = Data([0x41, 0x42, 0x43]) // "ABC"
        let file = LanguageModelV2File(
            mediaType: "application/octet-stream",
            data: .binary(binaryData)
        )

        // Note: JSONEncoder encodes Data as base64 by default
        let encoded = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(LanguageModelV2File.self, from: encoded)

        // After round-trip through JSON, binary Data becomes base64 string
        #expect(decoded.mediaType == "application/octet-stream")
        if case .base64(let base64String) = decoded.data {
            // Verify the base64 string decodes to our original data
            let decodedData = Data(base64Encoded: base64String)
            #expect(decodedData == binaryData)
        } else {
            #expect(Bool(false), "Expected base64 encoded data after JSON round-trip")
        }
    }

    // MARK: - Source

    @Test("Source: url variant round-trip")
    func source_urlVariant() throws {
        let pm: SharedV2ProviderMetadata = ["cache": ["hit": .bool(true)]]
        let source = LanguageModelV2Source.url(
            id: "url-123",
            url: "https://example.com/article",
            title: "Example Article",
            providerMetadata: pm
        )

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(LanguageModelV2Source.self, from: encoded)

        guard case let .url(id, url, title, metadata) = decoded else {
            #expect(Bool(false), "Expected url variant")
            return
        }
        #expect(id == "url-123")
        #expect(url == "https://example.com/article")
        #expect(title == "Example Article")
        #expect(metadata == pm)
    }

    @Test("Source: document variant round-trip")
    func source_documentVariant() throws {
        let source = LanguageModelV2Source.document(
            id: "doc-456",
            mediaType: "application/pdf",
            title: "Manual",
            filename: "manual.pdf",
            providerMetadata: nil
        )

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(LanguageModelV2Source.self, from: encoded)

        guard case let .document(id, mediaType, title, filename, _) = decoded else {
            #expect(Bool(false), "Expected document variant")
            return
        }
        #expect(id == "doc-456")
        #expect(mediaType == "application/pdf")
        #expect(title == "Manual")
        #expect(filename == "manual.pdf")
    }

    // MARK: - Content enum

    @Test("Content: text variant round-trip")
    func content_text() throws {
        let text = LanguageModelV2Text(text: "Content text", providerMetadata: nil)
        let content = LanguageModelV2Content.text(text)

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(LanguageModelV2Content.self, from: encoded)

        guard case .text(let decodedText) = decoded else {
            #expect(Bool(false), "Expected text content")
            return
        }
        #expect(decodedText.text == "Content text")
    }

    @Test("Content: reasoning variant round-trip")
    func content_reasoning() throws {
        let reasoning = LanguageModelV2Reasoning(text: "Thinking...", providerMetadata: nil)
        let content = LanguageModelV2Content.reasoning(reasoning)

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(LanguageModelV2Content.self, from: encoded)

        guard case .reasoning(let decodedReasoning) = decoded else {
            #expect(Bool(false), "Expected reasoning content")
            return
        }
        #expect(decodedReasoning.text == "Thinking...")
    }

    @Test("Content: file variant round-trip")
    func content_file() throws {
        let file = LanguageModelV2File(
            mediaType: "text/plain",
            data: .base64("abc")
        )
        let content = LanguageModelV2Content.file(file)

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(LanguageModelV2Content.self, from: encoded)

        guard case .file(let decodedFile) = decoded else {
            #expect(Bool(false), "Expected file content")
            return
        }
        #expect(decodedFile.mediaType == "text/plain")
    }

    @Test("Content: source variant round-trip")
    func content_source() throws {
        let source = LanguageModelV2Source.url(
            id: "a1",
            url: "https://example.com",
            title: nil,
            providerMetadata: nil
        )
        let content = LanguageModelV2Content.source(source)

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(LanguageModelV2Content.self, from: encoded)

        guard case .source(let decodedSource) = decoded else {
            #expect(Bool(false), "Expected source content")
            return
        }
        guard case let .url(id, url, _, _) = decodedSource else {
            #expect(Bool(false), "Expected url source variant")
            return
        }
        #expect(id == "a1")
        #expect(url == "https://example.com")
    }

    @Test("Content: toolCall variant round-trip")
    func content_toolCall() throws {
        let toolCall = LanguageModelV2ToolCall(
            toolCallId: "tc1",
            toolName: "calculator",
            input: "{\"x\":5}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let content = LanguageModelV2Content.toolCall(toolCall)

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(LanguageModelV2Content.self, from: encoded)

        guard case .toolCall(let decodedToolCall) = decoded else {
            #expect(Bool(false), "Expected toolCall content")
            return
        }
        #expect(decodedToolCall.toolCallId == "tc1")
        #expect(decodedToolCall.toolName == "calculator")
    }

    @Test("Content: toolResult variant round-trip")
    func content_toolResult() throws {
        let toolResult = LanguageModelV2ToolResult(
            toolCallId: "tc1",
            toolName: "calculator",
            result: ["answer": .number(42)],
            isError: false,
            providerExecuted: false,
            providerMetadata: nil
        )
        let content = LanguageModelV2Content.toolResult(toolResult)

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(LanguageModelV2Content.self, from: encoded)

        guard case .toolResult(let decodedToolResult) = decoded else {
            #expect(Bool(false), "Expected toolResult content")
            return
        }
        #expect(decodedToolResult.toolCallId == "tc1")
        #expect(decodedToolResult.result == ["answer": .number(42)])
    }
}
