import Foundation
import Testing
@testable import AISDKProvider

/**
 * Tests for LanguageModelV3ToolResult - focusing on V3-specific features
 *
 * V3 adds `preliminary?: Bool?` field for incremental tool result updates.
 * This is the ONLY functional difference from V2.
 */

@Suite("LanguageModelV3 ToolResult (V3-specific)")
struct LanguageModelV3ToolResultTests {

    // MARK: - preliminary field (NEW in V3)

    @Test("ToolResult: preliminary field encode/decode")
    func toolResult_preliminaryField() throws {
        let result = LanguageModelV3ToolResult(
            toolCallId: "call_123",
            toolName: "generateImage",
            result: ["status": .string("generating")],
            isError: false,
            providerExecuted: true,
            preliminary: true,  // NEW in V3
            providerMetadata: nil
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolResult.self, from: encoded)

        #expect(decoded.preliminary == true)
        #expect(decoded.toolCallId == "call_123")
        #expect(decoded.toolName == "generateImage")
    }

    @Test("ToolResult: preliminary false")
    func toolResult_preliminaryFalse() throws {
        let result = LanguageModelV3ToolResult(
            toolCallId: "call_final",
            toolName: "generateImage",
            result: ["imageUrl": .string("https://example.com/image.png")],
            preliminary: false  // Final result
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolResult.self, from: encoded)

        #expect(decoded.preliminary == false)
    }

    @Test("ToolResult: preliminary omitted (nil)")
    func toolResult_preliminaryOmitted() throws {
        let result = LanguageModelV3ToolResult(
            toolCallId: "call_123",
            toolName: "calculate",
            result: ["answer": .number(42)]
            // preliminary not specified (defaults to nil)
        )

        let encoded = try JSONEncoder().encode(result)
        let json = String(data: encoded, encoding: .utf8)!

        // Should not include preliminary field when nil
        #expect(!json.contains("preliminary"))

        let decoded = try JSONDecoder().decode(LanguageModelV3ToolResult.self, from: encoded)
        #expect(decoded.preliminary == nil)
    }

    @Test("ToolResult: incremental updates use case")
    func toolResult_incrementalUpdates() throws {
        // Simulates image generation with previews
        let preview1 = LanguageModelV3ToolResult(
            toolCallId: "img_gen_1",
            toolName: "generateImage",
            result: ["progress": .number(25), "preview": .string("low_res_v1")],
            preliminary: true
        )

        let preview2 = LanguageModelV3ToolResult(
            toolCallId: "img_gen_1",
            toolName: "generateImage",
            result: ["progress": .number(75), "preview": .string("mid_res_v1")],
            preliminary: true
        )

        let final = LanguageModelV3ToolResult(
            toolCallId: "img_gen_1",
            toolName: "generateImage",
            result: ["imageUrl": .string("https://example.com/final.png")],
            preliminary: false  // or nil - both indicate final result
        )

        // Encode all
        let enc = JSONEncoder()
        let data1 = try enc.encode(preview1)
        let data2 = try enc.encode(preview2)
        let dataFinal = try enc.encode(final)

        // Decode and verify
        let dec = JSONDecoder()
        let decoded1 = try dec.decode(LanguageModelV3ToolResult.self, from: data1)
        let decoded2 = try dec.decode(LanguageModelV3ToolResult.self, from: data2)
        let decodedFinal = try dec.decode(LanguageModelV3ToolResult.self, from: dataFinal)

        #expect(decoded1.preliminary == true)
        #expect(decoded2.preliminary == true)
        #expect(decodedFinal.preliminary == false)

        // All should have same toolCallId (replacing each other)
        #expect(decoded1.toolCallId == "img_gen_1")
        #expect(decoded2.toolCallId == "img_gen_1")
        #expect(decodedFinal.toolCallId == "img_gen_1")
    }

    // MARK: - V2 compatibility (all V2 fields still work)

    @Test("ToolResult: V2 fields still work in V3")
    func toolResult_v2Compatibility() throws {
        // Create V3 ToolResult with only V2 fields (no preliminary)
        let result = LanguageModelV3ToolResult(
            toolCallId: "call_v2",
            toolName: "searchWeb",
            result: ["results": .array([.string("result1"), .string("result2")])],
            isError: false,
            providerExecuted: true,
            providerMetadata: ["provider": ["cached": .bool(true)]]
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolResult.self, from: encoded)

        // All V2 fields work as before
        #expect(decoded.toolCallId == "call_v2")
        #expect(decoded.toolName == "searchWeb")
        #expect(decoded.isError == false)
        #expect(decoded.providerExecuted == true)
        #expect(decoded.providerMetadata != nil)

        // preliminary defaults to nil when not specified
        #expect(decoded.preliminary == nil)
    }
}
