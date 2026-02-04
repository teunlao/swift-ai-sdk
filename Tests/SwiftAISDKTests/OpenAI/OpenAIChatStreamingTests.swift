import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

/**
 OpenAI Chat Streaming Tests - Batch 15 (annotations, tool deltas)

 Port of `@ai-sdk/openai/src/chat/openai-chat-language-model.test.ts`.
 */

@Suite("OpenAI Chat Streaming")
struct OpenAIChatStreamingTests {

    @Test("Stream annotations/citations")
    func testStreamAnnotationsCitations() async throws {
        let events = [
            "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1694268190,\"model\":\"gpt-4o-mini-2024-07-18\",\"system_fingerprint\":\"fp_f33667828e\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\",\"refusal\":null},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1694268190,\"model\":\"gpt-4o-mini-2024-07-18\",\"system_fingerprint\":\"fp_f33667828e\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Based on search results\",\"annotations\":[{\"type\":\"url_citation\",\"text\":\"Based on search results\",\"start_index\":0,\"end_index\":22,\"url\":\"https://example.com/doc1.pdf\",\"title\":\"Document 1\"}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1694268190,\"model\":\"gpt-4o-mini-2024-07-18\",\"system_fingerprint\":\"fp_f33667828e\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}",
            "data: [DONE]"
        ]

        let mockFetch: FetchFunction = { request in
            let sseData = events.joined(separator: "\n\n").data(using: .utf8)!
            let httpResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "text/event-stream"]
            )!
            return FetchResponse(body: .data(sseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let prompt: LanguageModelV3Prompt = [.system(content: "Test", providerOptions: nil)]
        let stream = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: prompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream.stream {
            parts.append(part)
        }

        // Verify BOTH text deltas: empty string AND "Based on search results"
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(id: "0", delta: let delta, providerMetadata: _) = part {
                return delta
            }
            return nil
        }

        #expect(textDeltas.count == 2)
        #expect(textDeltas[0] == "")
        #expect(textDeltas[1] == "Based on search results")

        // Verify source (annotation)
        let hasSource = parts.contains(where: { part in
            if case .source(let source) = part,
               case .url(id: _, url: "https://example.com/doc1.pdf", title: "Document 1", providerMetadata: _) = source {
                return true
            }
            return false
        })
        #expect(hasSource)

        // Verify finish
        let hasFinish = parts.contains { part in
            guard case .finish(finishReason: let finishReason, usage: _, providerMetadata: _) = part else {
                return false
            }
            return finishReason.unified == .stop && finishReason.raw == "stop"
        }
        #expect(hasFinish)
    }

    @Test("Stream tool deltas")
    func testStreamToolDeltas() async throws {
        let events = [
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"index\":0,\"id\":\"call_O17Uplv4lJvD6DVdIvFFeRMw\",\"type\":\"function\",\"function\":{\"name\":\"test-tool\",\"arguments\":\"\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"value\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\":\\\"\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"Spark\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"le\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\" Day\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}"#,
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"tool_calls\"}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":53,\"completion_tokens\":17,\"total_tokens\":70}}",
            "data: [DONE]"
        ]

        let mockFetch: FetchFunction = { request in
            let sseData = events.joined(separator: "\n\n").data(using: .utf8)!
            let httpResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "text/event-stream"]
            )!
            return FetchResponse(body: .data(sseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )
        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let prompt: LanguageModelV3Prompt = [.user(content: [.text(LanguageModelV3TextPart(text: "Test"))], providerOptions: nil)]
        let stream = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: prompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream.stream {
            parts.append(part)
        }

        // Extract tool-input-delta parts
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case .toolInputDelta(id: _, delta: let delta, providerMetadata: _) = part {
                return delta
            }
            return nil
        }

        // Verify all 8 deltas (including initial empty string)
        #expect(toolInputDeltas.count == 8)
        #expect(toolInputDeltas[0] == "")
        #expect(toolInputDeltas[1] == "{\"")
        #expect(toolInputDeltas[2] == "value")
        #expect(toolInputDeltas[3] == "\":\"")
        #expect(toolInputDeltas[4] == "Spark")
        #expect(toolInputDeltas[5] == "le")
        #expect(toolInputDeltas[6] == " Day")
        #expect(toolInputDeltas[7] == "\"}")

        // Verify tool call completion
        let hasToolCall = parts.contains(where: { part in
            if case .toolCall(let toolCall) = part {
                return toolCall.toolCallId == "call_O17Uplv4lJvD6DVdIvFFeRMw" &&
                       toolCall.toolName == "test-tool" &&
                       toolCall.input == "{\"value\":\"Sparkle Day\"}"
            }
            return false
        })
        #expect(hasToolCall)

        // Verify finish
        let hasFinish = parts.contains { part in
            guard case .finish(finishReason: let finishReason, usage: _, providerMetadata: _) = part else {
                return false
            }
            return finishReason.unified == .toolCalls && finishReason.raw == "tool_calls"
        }
        #expect(hasFinish)
    }

    // MARK: - Batch 16: Tool Call Edge Cases

    @Test("Stream tool deltas with arguments in first chunk")
    func testStreamToolDeltasArgumentsInFirstChunk() async throws {
        let events = [
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"index\":0,\"id\":\"call_O17Uplv4lJvD6DVdIvFFeRMw\",\"type\":\"function\",\"function\":{\"name\":\"test-tool\",\"arguments\":\"{\\\"\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"va\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"lue\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\":\\\"\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"Spark\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"le\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\" Day\"}}]},\"logprobs\":null,\"finish_reason\":null}]}",
            #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}"#,
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"tool_calls\"}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":53,\"completion_tokens\":17,\"total_tokens\":70}}",
            "data: [DONE]"
        ]

        let mockFetch: FetchFunction = { request in
            let sseData = events.joined(separator: "\n\n").data(using: .utf8)!
            let httpResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "text/event-stream"]
            )!
            return FetchResponse(body: .data(sseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )
        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let prompt: LanguageModelV3Prompt = [.user(content: [.text(LanguageModelV3TextPart(text: "Test"))], providerOptions: nil)]
        let stream = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: prompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream.stream {
            parts.append(part)
        }

        // Extract tool-input-delta parts
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case .toolInputDelta(id: _, delta: let delta, providerMetadata: _) = part {
                return delta
            }
            return nil
        }

        // Verify all 8 deltas (first chunk has "{\"" instead of empty)
        #expect(toolInputDeltas.count == 8)
        #expect(toolInputDeltas[0] == "{\"")
        #expect(toolInputDeltas[1] == "va")
        #expect(toolInputDeltas[2] == "lue")
        #expect(toolInputDeltas[3] == "\":\"")
        #expect(toolInputDeltas[4] == "Spark")
        #expect(toolInputDeltas[5] == "le")
        #expect(toolInputDeltas[6] == " Day")
        #expect(toolInputDeltas[7] == "\"}")

        // Verify tool call completion
        let hasToolCall = parts.contains(where: { part in
            if case .toolCall(let toolCall) = part {
                return toolCall.toolCallId == "call_O17Uplv4lJvD6DVdIvFFeRMw" &&
                       toolCall.toolName == "test-tool" &&
                       toolCall.input == "{\"value\":\"Sparkle Day\"}"
            }
            return false
        })
        #expect(hasToolCall)
    }

    @Test("Not duplicate tool calls when there is an additional empty chunk after completion")
    func testNotDuplicateToolCallsWithEmptyChunk() async throws {
        let events = [
            "data: {\"id\":\"chat-123\",\"object\":\"chat.completion.chunk\",\"created\":1733162241,\"model\":\"meta/llama-3.1-8b-instruct:fp8\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"logprobs\":null,\"finish_reason\":null}],\"usage\":{\"prompt_tokens\":226,\"total_tokens\":226,\"completion_tokens\":0}}",
            "data: {\"id\":\"chat-123\",\"object\":\"chat.completion.chunk\",\"created\":1733162241,\"model\":\"meta/llama-3.1-8b-instruct:fp8\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"id\":\"chatcmpl-tool-123\",\"type\":\"function\",\"index\":0,\"function\":{\"name\":\"searchGoogle\"}}]},\"logprobs\":null,\"finish_reason\":null}],\"usage\":{\"prompt_tokens\":226,\"total_tokens\":233,\"completion_tokens\":7}}",
            #"data: {"id":"chat-123","object":"chat.completion.chunk","created":1733162241,"model":"meta/llama-3.1-8b-instruct:fp8","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\": \""}}]},"logprobs":null,"finish_reason":null}],"usage":{"prompt_tokens":226,"total_tokens":241,"completion_tokens":15}}"#,
            "data: {\"id\":\"chat-123\",\"object\":\"chat.completion.chunk\",\"created\":1733162241,\"model\":\"meta/llama-3.1-8b-instruct:fp8\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"latest\"}}]},\"logprobs\":null,\"finish_reason\":null}],\"usage\":{\"prompt_tokens\":226,\"total_tokens\":242,\"completion_tokens\":16}}",
            "data: {\"id\":\"chat-123\",\"object\":\"chat.completion.chunk\",\"created\":1733162241,\"model\":\"meta/llama-3.1-8b-instruct:fp8\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\" news\"}}]},\"logprobs\":null,\"finish_reason\":null}],\"usage\":{\"prompt_tokens\":226,\"total_tokens\":243,\"completion_tokens\":17}}",
            "data: {\"id\":\"chat-123\",\"object\":\"chat.completion.chunk\",\"created\":1733162241,\"model\":\"meta/llama-3.1-8b-instruct:fp8\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\" on\"}}]},\"logprobs\":null,\"finish_reason\":null}],\"usage\":{\"prompt_tokens\":226,\"total_tokens\":244,\"completion_tokens\":18}}",
            #"data: {"id":"chat-123","object":"chat.completion.chunk","created":1733162241,"model":"meta/llama-3.1-8b-instruct:fp8","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":" ai\"}"}}]},"logprobs":null,"finish_reason":null}],"usage":{"prompt_tokens":226,"total_tokens":245,"completion_tokens":19}}"#,
            // Empty arguments chunk AFTER tool call is already completed
            "data: {\"id\":\"chat-123\",\"object\":\"chat.completion.chunk\",\"created\":1733162241,\"model\":\"meta/llama-3.1-8b-instruct:fp8\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\"}}]},\"logprobs\":null,\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":226,\"total_tokens\":246,\"completion_tokens\":20}}",
            "data: {\"id\":\"chat-123\",\"object\":\"chat.completion.chunk\",\"created\":1733162241,\"model\":\"meta/llama-3.1-8b-instruct:fp8\",\"choices\":[],\"usage\":{\"prompt_tokens\":226,\"total_tokens\":246,\"completion_tokens\":20}}",
            "data: [DONE]"
        ]

        let mockFetch: FetchFunction = { request in
            let sseData = events.joined(separator: "\n\n").data(using: .utf8)!
            let httpResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "text/event-stream"]
            )!
            return FetchResponse(body: .data(sseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )
        let model = OpenAIChatLanguageModel(modelId: "meta/llama-3.1-8b-instruct:fp8", config: config)

        let prompt: LanguageModelV3Prompt = [.user(content: [.text(LanguageModelV3TextPart(text: "Test"))], providerOptions: nil)]
        let stream = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: prompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream.stream {
            parts.append(part)
        }

        // Extract tool-input-delta parts - should have 5, not 6 (empty chunk should not produce delta)
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case .toolInputDelta(id: _, delta: let delta, providerMetadata: _) = part {
                return delta
            }
            return nil
        }

        #expect(toolInputDeltas.count == 5)
        #expect(toolInputDeltas[0] == "{\"query\": \"")
        #expect(toolInputDeltas[1] == "latest")
        #expect(toolInputDeltas[2] == " news")
        #expect(toolInputDeltas[3] == " on")
        #expect(toolInputDeltas[4] == " ai\"}")

        // Verify exactly 1 tool call (no duplicates)
        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let toolCall) = part {
                return toolCall
            }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].toolCallId == "chatcmpl-tool-123")
        #expect(toolCalls[0].toolName == "searchGoogle")
        #expect(toolCalls[0].input == "{\"query\": \"latest news on ai\"}")

        // Verify finish
        let hasFinish = parts.contains { part in
            guard case .finish(finishReason: let finishReason, usage: _, providerMetadata: _) = part else {
                return false
            }
            return finishReason.unified == .toolCalls && finishReason.raw == "tool_calls"
        }
        #expect(hasFinish)
    }

    @Test("Stream tool call that is sent in one chunk")
    func testStreamToolCallInOneChunk() async throws {
        let events = [
            #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"role":"assistant","content":null,"tool_calls":[{"index":0,"id":"call_O17Uplv4lJvD6DVdIvFFeRMw","type":"function","function":{"name":"test-tool","arguments":"{\"value\":\"Sparkle Day\"}"}}]},"logprobs":null,"finish_reason":null}]}"#,
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"tool_calls\"}]}",
            "data: {\"id\":\"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":53,\"completion_tokens\":17,\"total_tokens\":70}}",
            "data: [DONE]"
        ]

        let mockFetch: FetchFunction = { request in
            let sseData = events.joined(separator: "\n\n").data(using: .utf8)!
            let httpResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "text/event-stream"]
            )!
            return FetchResponse(body: .data(sseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )
        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let prompt: LanguageModelV3Prompt = [.user(content: [.text(LanguageModelV3TextPart(text: "Test"))], providerOptions: nil)]
        let stream = try await model.doStream(
            options: LanguageModelV3CallOptions(prompt: prompt)
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream.stream {
            parts.append(part)
        }

        // Should have exactly 1 tool-input-delta with complete JSON
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case .toolInputDelta(id: _, delta: let delta, providerMetadata: _) = part {
                return delta
            }
            return nil
        }

        #expect(toolInputDeltas.count == 1)
        #expect(toolInputDeltas[0] == "{\"value\":\"Sparkle Day\"}")

        // Verify tool call
        let hasToolCall = parts.contains(where: { part in
            if case .toolCall(let toolCall) = part {
                return toolCall.toolCallId == "call_O17Uplv4lJvD6DVdIvFFeRMw" &&
                       toolCall.toolName == "test-tool" &&
                       toolCall.input == "{\"value\":\"Sparkle Day\"}"
            }
            return false
        })
        #expect(hasToolCall)

        // Verify finish
        let hasFinish = parts.contains { part in
            guard case .finish(finishReason: let finishReason, usage: _, providerMetadata: _) = part else {
                return false
            }
            return finishReason.unified == .toolCalls && finishReason.raw == "tool_calls"
        }
        #expect(hasFinish)
    }

    @Test("Send request body for streaming")
    func testSendRequestBodyStreaming() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
            func store(_ body: [String: Any]) { self.body = body }
            func value() -> [String: Any]? { body }
        }

        let capture = RequestCapture()

        let events = [
            "data: {\"id\":\"chatcmpl-1\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-3.5-turbo\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}",
            "data: {\"id\":\"chatcmpl-1\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-3.5-turbo\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
            "data: {\"id\":\"chatcmpl-1\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-3.5-turbo\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}",
            "data: [DONE]"
        ]

        let mockFetch: FetchFunction = { request in
            if let bodyData = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                await capture.store(json)
            }

            let streamBody = ProviderHTTPResponseBody.stream(AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                    continuation.yield(Data("\n\n".utf8))
                }
                continuation.finish()
            })

            return FetchResponse(
                body: streamBody,
                urlResponse: HTTPURLResponse(
                    url: URL(string: "https://api.openai.com")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                includeRawChunks: false
            )
        )

        guard let body = await capture.value() else {
            Issue.record("Expected request body")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")
        #expect(body["stream"] as? Bool == true)

        if let streamOptions = body["stream_options"] as? [String: Any] {
            #expect(streamOptions["include_usage"] as? Bool == true)
        } else {
            Issue.record("Expected stream_options")
        }

        if let messages = body["messages"] as? [[String: Any]] {
            #expect(messages.count == 1)
            #expect(messages[0]["role"] as? String == "user")
            #expect(messages[0]["content"] as? String == "Hello")
        } else {
            Issue.record("Expected messages array")
        }
    }

}
