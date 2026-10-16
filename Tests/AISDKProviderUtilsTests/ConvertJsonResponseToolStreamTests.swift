import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("convertJsonResponseToolStream")
struct ConvertJsonResponseToolStreamTests {
    private func run(_ parts: [LanguageModelV4StreamPart]) async throws -> [LanguageModelV4StreamPart] {
        let source = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        var output: [LanguageModelV4StreamPart] = []
        for try await part in convertJsonResponseToolStream(source, toolName: "json") {
            output.append(part)
        }
        return output
    }

    private let usage = LanguageModelV4Usage()

    @Test("turns the response tool into text, drops conversational text and finishes with stop")
    func convertsResponseToolToText() async throws {
        let output = try await run([
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "Sure!", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .toolInputStart(id: "c1", toolName: "json", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputDelta(id: "c1", delta: #"{"a":1}"#, providerMetadata: nil),
            .toolInputEnd(id: "c1", providerMetadata: nil),
            .toolCall(.init(toolCallId: "c1", toolName: "json", input: #"{"a":1}"#)),
            .finish(finishReason: .init(unified: .toolCalls, raw: "tool_calls"), usage: usage, providerMetadata: nil),
        ])

        #expect(output == [
            .textStart(id: "c1", providerMetadata: nil),
            .textDelta(id: "c1", delta: #"{"a":1}"#, providerMetadata: nil),
            .textEnd(id: "c1", providerMetadata: nil),
            .finish(finishReason: .init(unified: .stop, raw: "tool_calls"), usage: usage, providerMetadata: nil),
        ])
    }

    @Test("passes application tool calls through and keeps the tool-calls finish reason")
    func keepsApplicationToolCalls() async throws {
        let applicationCall = LanguageModelV4ToolCall(toolCallId: "c2", toolName: "weather", input: "{}")
        let output = try await run([
            .toolCall(.init(toolCallId: "c1", toolName: "json", input: #"{"a":1}"#)),
            .toolCall(applicationCall),
            .finish(finishReason: .init(unified: .toolCalls), usage: usage, providerMetadata: nil),
        ])

        #expect(output == [
            .textDelta(id: "c1", delta: #"{"a":1}"#, providerMetadata: nil),
            .textEnd(id: "c1", providerMetadata: nil),
            .toolCall(applicationCall),
            .finish(finishReason: .init(unified: .toolCalls), usage: usage, providerMetadata: nil),
        ])
    }
}

@Suite("isValidHostnamePart")
struct IsValidHostnamePartTests {
    @Test("accepts hostname labels and rejects values that change the destination")
    func validatesHostnameParts() {
        #expect(isValidHostnamePart("us-east-1"))
        #expect(isValidHostnamePart("A1"))
        #expect(isValidHostnamePart(String(repeating: "a", count: 63)))

        #expect(!isValidHostnamePart(""))
        #expect(!isValidHostnamePart("-region"))
        #expect(!isValidHostnamePart("region-"))
        #expect(!isValidHostnamePart(String(repeating: "a", count: 64)))
        #expect(!isValidHostnamePart("evil.example.com/#"))
        #expect(!isValidHostnamePart("user@localhost:8080/#"))
        #expect(!isValidHostnamePart("region\n"))
    }
}
