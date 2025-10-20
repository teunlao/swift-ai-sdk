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
        let hasFinish = parts.contains(where: { part in
            if case .finish(finishReason: .stop, usage: _, providerMetadata: _) = part {
                return true
            }
            return false
        })
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

        // Verify all 7 deltas
        #expect(toolInputDeltas.count == 7)
        #expect(toolInputDeltas[0] == "{\"")
        #expect(toolInputDeltas[1] == "value")
        #expect(toolInputDeltas[2] == "\":\"")
        #expect(toolInputDeltas[3] == "Spark")
        #expect(toolInputDeltas[4] == "le")
        #expect(toolInputDeltas[5] == " Day")
        #expect(toolInputDeltas[6] == "\"}")

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
        let hasFinish = parts.contains(where: { part in
            if case .finish(finishReason: .toolCalls, usage: _, providerMetadata: _) = part {
                return true
            }
            return false
        })
        #expect(hasFinish)
    }
}
