import Testing
@testable import AISDKProvider
import Foundation

@Test("StreamPart round-trip: text/reasoning with providerMetadata")
func streamPart_text_reasoning_roundTrip() throws {
    let pm: SharedV2ProviderMetadata = [
        "provider": [
            "k": .string("v"),
            "n": .number(1)
        ]
    ]

    let parts: [LanguageModelV2StreamPart] = [
        .textStart(id: "t1", providerMetadata: pm),
        .textDelta(id: "t1", delta: "Hello", providerMetadata: pm),
        .textEnd(id: "t1", providerMetadata: pm),
        .reasoningStart(id: "r1", providerMetadata: pm),
        .reasoningDelta(id: "r1", delta: "why", providerMetadata: pm),
        .reasoningEnd(id: "r1", providerMetadata: pm),
        .streamStart(warnings: [.unsupportedSetting(setting: "foo", details: nil)])
    ]

    let enc = JSONEncoder()
    let dec = JSONDecoder()

    for p in parts {
        let data = try enc.encode(p)
        let back = try dec.decode(LanguageModelV2StreamPart.self, from: data)
        #expect(back == p)
    }
}

@Test("StreamPart round-trip: tool-input start/delta/end + tool-call/result")
func streamPart_toolInput_and_callResult_roundTrip() throws {
    let pm: SharedV2ProviderMetadata = [
        "openai": ["foo": .string("bar")]
    ]

    let call = LanguageModelV2ToolCall(
        toolCallId: "c1",
        toolName: "search",
        input: "{\"q\":\"swift\"}",
        providerExecuted: true,
        providerMetadata: pm
    )
    let result = LanguageModelV2ToolResult(
        toolCallId: "c1",
        toolName: "search",
        result: ["hits": .array([.number(1), .number(2)])],
        isError: nil,
        providerExecuted: true,
        providerMetadata: pm
    )

    let parts: [LanguageModelV2StreamPart] = [
        .toolInputStart(id: "c1", toolName: "search", providerMetadata: pm, providerExecuted: true),
        .toolInputDelta(id: "c1", delta: "{\"q\":\"swi", providerMetadata: nil),
        .toolInputDelta(id: "c1", delta: "ft\"}", providerMetadata: nil),
        .toolInputEnd(id: "c1", providerMetadata: pm),
        .toolCall(call),
        .toolResult(result)
    ]

    let enc = JSONEncoder()
    let dec = JSONDecoder()
    for p in parts {
        let data = try enc.encode(p)
        let back = try dec.decode(LanguageModelV2StreamPart.self, from: data)
        #expect(back == p)
    }
}

@Test("StreamPart decode: response-metadata from ISO-8601 timestamp JSON")
func streamPart_responseMetadata_iso8601_decode() throws {
    let json = """
    {"type":"response-metadata","id":"r1","modelId":"gpt-xyz","timestamp":"2025-10-12T00:00:00Z"}
    """.data(using: .utf8)!
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    let part = try dec.decode(LanguageModelV2StreamPart.self, from: json)
    guard case .responseMetadata(let id, let modelId, let timestamp) = part else {
        #expect(Bool(false), "Expected response-metadata part")
        return
    }
    #expect(id == "r1")
    #expect(modelId == "gpt-xyz")
    #expect(timestamp != nil)
}

@Test("StreamPart round-trip: finish with usage (optional fields)")
func streamPart_finish_usage_roundTrip() throws {
    let usage = LanguageModelV2Usage(
        inputTokens: 10,
        outputTokens: 5,
        totalTokens: 16,
        reasoningTokens: 1,
        cachedInputTokens: nil
    )
    let part: LanguageModelV2StreamPart = .finish(
        finishReason: .stop,
        usage: usage,
        providerMetadata: ["provider": ["note": .string("ok")]]
    )
    let data = try JSONEncoder().encode(part)
    let back = try JSONDecoder().decode(LanguageModelV2StreamPart.self, from: data)
    #expect(back == part)
}

@Test("StreamPart round-trip: raw + error arbitrary JSON payloads")
func streamPart_raw_error_roundTrip() throws {
    let raw: LanguageModelV2StreamPart = .raw(rawValue: [
        "arr": .array([.number(1), .string("x")]),
        "obj": .object(["a": .bool(true)])
    ])
    let err: LanguageModelV2StreamPart = .error(error: .object([
        "code": .string("UpstreamError"),
        "details": .array([.string("bad input"), .number(400)])
    ]))

    let enc = JSONEncoder()
    let dec = JSONDecoder()
    for p in [raw, err] {
        let data = try enc.encode(p)
        let back = try dec.decode(LanguageModelV2StreamPart.self, from: data)
        #expect(back == p)
    }
}

