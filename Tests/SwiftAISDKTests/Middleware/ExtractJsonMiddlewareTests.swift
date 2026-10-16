import Foundation
import Testing
import AISDKProvider
import SwiftAISDK

private func textStream(_ deltas: [String]) -> [LanguageModelV4StreamPart] {
    [.textStart(id: "1", providerMetadata: nil)]
        + deltas.map { .textDelta(id: "1", delta: $0, providerMetadata: nil) }
        + [.textEnd(id: "1", providerMetadata: nil), middlewareTestFinish]
}

private let stripPrefixAndSuffix = ExtractJsonOptions(transform: { text in
    text.replacingOccurrences(of: "PREFIX", with: "").replacingOccurrences(of: "SUFFIX", with: "")
})

@Suite("extractJsonMiddleware")
struct ExtractJsonMiddlewareTests {
    @Test("strips markdown fences from generated text parts only", arguments: [
        ("```json\n{\"value\": \"test\"}\n```", "{\"value\": \"test\"}"),
        ("```\n{\"value\": \"test\"}\n```", "{\"value\": \"test\"}"),
        ("{\"value\": \"test\"}", "{\"value\": \"test\"}"),
    ])
    func generate(_ input: String, _ expected: String) async throws {
        let reasoning = LanguageModelV4Content.reasoning(LanguageModelV4Reasoning(text: "```json\nthinking\n```"))
        let content = try await generateThroughMiddleware(
            extractJsonMiddleware(),
            [reasoning, .text(LanguageModelV4Text(text: input, providerMetadata: ["p": ["k": .string("v")]]))]
        )

        #expect(content == [
            reasoning,
            .text(LanguageModelV4Text(text: expected, providerMetadata: ["p": ["k": .string("v")]])),
        ])
    }

    @Test("applies a custom transform instead of fence stripping")
    func generateCustomTransform() async throws {
        let content = try await generateThroughMiddleware(
            extractJsonMiddleware(options: stripPrefixAndSuffix),
            [.text(LanguageModelV4Text(text: "PREFIX{\"value\": \"test\"}SUFFIX"))]
        )

        #expect(content == [.text(LanguageModelV4Text(text: "{\"value\": \"test\"}"))])
    }

    @Test("strips a fence split across deltas, holding text-start until the prefix is known")
    func streamSplitFence() async throws {
        let output = try await streamThroughMiddleware(
            extractJsonMiddleware(),
            textStream(["`", "``", "json\n", "{\"value\": \"test\"}", "\n`", "``"])
        )

        #expect(output == [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "{\"value\": \"test\"}", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }

    @Test("strips a closing fence followed by trailing whitespace in any chunk layout")
    func streamTrailingWhitespace() async throws {
        let json = "{\"value\": \"test\"}"
        for trailingWhitespace in [String(repeating: " ", count: 20), String(repeating: "\n", count: 20)] {
            let text = "```json\n\(json)\n```" + trailingWhitespace
            for chunks in [[text], text.map(String.init), ["```json\n\(json)\n", "```", trailingWhitespace]] {
                let output = try await streamThroughMiddleware(extractJsonMiddleware(), textStream(chunks))
                #expect(textDeltas(output) == json)
            }
        }
    }

    @Test("streams unfenced text unchanged", arguments: [
        ["there", " altogether?"],
        ["`code`"],
        [String(repeating: " ", count: 100) + "x"],
    ])
    func streamUnfenced(_ deltas: [String]) async throws {
        let output = try await streamThroughMiddleware(extractJsonMiddleware(), textStream(deltas))

        #expect(textDeltas(output) == deltas.joined())
    }

    @Test("buffers a text part for a custom transform and emits it at text-end")
    func streamCustomTransform() async throws {
        let output = try await streamThroughMiddleware(
            extractJsonMiddleware(options: stripPrefixAndSuffix),
            textStream(["PREFIX", "{\"value\": \"test\"}", "SUFFIX"])
        )

        #expect(output == [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "{\"value\": \"test\"}", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }

    @Test("emits text-start when the text part ends while the prefix is undecided")
    func streamEndsInPrefixPhase() async throws {
        let output = try await streamThroughMiddleware(extractJsonMiddleware(), textStream(["``"]))

        #expect(output == [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "``", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }

    @Test("forwards a text-delta without a text-start unchanged")
    func streamUnknownTextPart() async throws {
        let delta = LanguageModelV4StreamPart.textDelta(id: "unknown", delta: "```json\n", providerMetadata: nil)
        let output = try await streamThroughMiddleware(extractJsonMiddleware(), [delta, middlewareTestFinish])

        #expect(output == [delta, middlewareTestFinish])
    }
}
