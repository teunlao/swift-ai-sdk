import Foundation
import Testing
import AISDKProvider
import SwiftAISDK

private func middleware(
    _ tagName: ExtractReasoningOptions.TagName = .init("think"),
    separator: String = "\n",
    startWithReasoning: Bool = false
) -> LanguageModelV4Middleware {
    extractReasoningMiddleware(options: ExtractReasoningOptions(
        tagName: tagName,
        separator: separator,
        startWithReasoning: startWithReasoning
    ))
}

private func reasoningAndText(_ content: [LanguageModelV4Content]) -> (reasoning: [String], text: [String]) {
    var reasoning: [String] = []
    var text: [String] = []
    for part in content {
        switch part {
        case .reasoning(let part): reasoning.append(part.text)
        case .text(let part): text.append(part.text)
        default: break
        }
    }
    return (reasoning, text)
}

private func textStream(_ id: String, _ deltas: [String]) -> [LanguageModelV4StreamPart] {
    [.textStart(id: id, providerMetadata: nil)]
        + deltas.map { .textDelta(id: id, delta: $0, providerMetadata: nil) }
        + [.textEnd(id: id, providerMetadata: nil), middlewareTestFinish]
}

@Suite("extractReasoningMiddleware")
struct ExtractReasoningMiddlewareTests {
    struct DelimiterCase: Sendable, CustomTestStringConvertible {
        let name: String
        let tagName: ExtractReasoningOptions.TagName
        var separator = "\n"
        var startWithReasoning = false
        let input: String
        let reasoning: String?
        let text: String

        var testDescription: String { name }
    }

    static let gemma = try! ExtractReasoningOptions.TagName(opening: "<|channel>thought\n", closing: "<channel|>")

    static let delimiterCases: [DelimiterCase] = [
        DelimiterCase(
            name: "Gemma thought channel",
            tagName: gemma,
            input: "<|channel>thought\nChecking the sum.\nIt is four.<channel|>4",
            reasoning: "Checking the sum.\nIt is four.",
            text: "4"
        ),
        DelimiterCase(
            name: "empty Gemma thought channel",
            tagName: gemma,
            input: "<|channel>thought\n<channel|>4",
            reasoning: "",
            text: "4"
        ),
        DelimiterCase(
            name: "omitted opening delimiter",
            tagName: gemma,
            startWithReasoning: true,
            input: "Checking the sum.<channel|>4",
            reasoning: "Checking the sum.",
            text: "4"
        ),
        DelimiterCase(
            name: "literal regex metacharacters",
            tagName: try! .init(opening: "[.*+?^${}()|\\]", closing: "(end.*+?^${}|\\)"),
            input: "[.*+?^${}()|\\]Checking the sum.(end.*+?^${}|\\)4",
            reasoning: "Checking the sum.",
            text: "4"
        ),
        DelimiterCase(
            name: "multiple reasoning blocks and a custom separator",
            tagName: gemma,
            separator: " / ",
            input: "Before<|channel>thought\nFirst<channel|>Between<|channel>thought\nSecond<channel|>After",
            reasoning: "First / Second",
            text: "Before / Between / After"
        ),
        DelimiterCase(
            name: "text without delimiters",
            tagName: gemma,
            input: "4",
            reasoning: nil,
            text: "4"
        ),
        DelimiterCase(
            name: "literal regex metacharacters in a string tag name",
            tagName: .init("think|reason"),
            input: "<think|reason>Checking the sum.</think|reason>4",
            reasoning: "Checking the sum.",
            text: "4"
        ),
    ]

    @Test("extracts reasoning from generated text", arguments: delimiterCases)
    func generate(_ testCase: DelimiterCase) async throws {
        let content = try await generateThroughMiddleware(
            middleware(testCase.tagName, separator: testCase.separator, startWithReasoning: testCase.startWithReasoning),
            [.text(LanguageModelV4Text(text: testCase.input))]
        )

        let extracted = reasoningAndText(content)
        #expect(extracted.reasoning == (testCase.reasoning.map { [$0] } ?? []))
        #expect(extracted.text == [testCase.text])
    }

    @Test("extracts reasoning when every delimiter character is streamed separately", arguments: delimiterCases)
    func streamCharacterByCharacter(_ testCase: DelimiterCase) async throws {
        let output = try await streamThroughMiddleware(
            middleware(testCase.tagName, separator: testCase.separator, startWithReasoning: testCase.startWithReasoning),
            textStream("text-0", testCase.input.map(String.init))
        )

        #expect(textDeltas(output) == testCase.text)
        #expect(reasoningDeltas(output) == (testCase.reasoning == "" ? nil : testCase.reasoning))

        let starts = output.compactMap { part -> String? in
            if case .reasoningStart(let id, _) = part { return id }
            return nil
        }
        let ends = output.compactMap { part -> String? in
            if case .reasoningEnd(let id, _) = part { return id }
            return nil
        }
        #expect(starts == ends)
        #expect(starts.isEmpty == (testCase.reasoning == nil))
    }

    @Test("rejects empty delimiters")
    func emptyDelimiters() {
        #expect(throws: InvalidArgumentError.self) {
            try ExtractReasoningOptions.TagName(opening: "", closing: "<channel|>")
        }
        #expect(throws: InvalidArgumentError.self) {
            try ExtractReasoningOptions.TagName(opening: "<|channel>thought\n", closing: "")
        }
    }

    @Test("joins multiple <think> sections with the separator and prepends the tag when starting with reasoning")
    func generateMultipleAndStartWithReasoning() async throws {
        let multiple = try await generateThroughMiddleware(
            middleware(),
            [.text(LanguageModelV4Text(text: "<think>analyzing the request</think>Here is the response<think>thinking about the response</think>more"))]
        )
        #expect(reasoningAndText(multiple).reasoning == ["analyzing the request\nthinking about the response"])
        #expect(reasoningAndText(multiple).text == ["Here is the response\nmore"])

        let started = try await generateThroughMiddleware(
            middleware(startWithReasoning: true),
            [.text(LanguageModelV4Text(text: "analyzing the request</think>Here is the response"))]
        )
        #expect(reasoningAndText(started).reasoning == ["analyzing the request"])
        #expect(reasoningAndText(started).text == ["Here is the response"])
    }

    @Test("streams split <think> tags as reasoning before the delayed text-start")
    func streamSplitTags() async throws {
        let output = try await streamThroughMiddleware(
            middleware(),
            textStream("1", ["<think>", "ana", "lyzing the request", "</think>", "Here", " is the response"])
        )

        #expect(output == [
            .reasoningStart(id: "reasoning-0", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-0", delta: "ana", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-0", delta: "lyzing the request", providerMetadata: nil),
            .reasoningEnd(id: "reasoning-0", providerMetadata: nil),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Here", providerMetadata: nil),
            .textDelta(id: "1", delta: " is the response", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }

    @Test("separates sections of a single chunk and numbers reasoning blocks")
    func streamSingleChunkWithMultipleTags() async throws {
        let output = try await streamThroughMiddleware(
            middleware(),
            textStream("1", ["<think>a</think>b<think>c</think>d"])
        )

        #expect(output == [
            .reasoningStart(id: "reasoning-0", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-0", delta: "a", providerMetadata: nil),
            .reasoningEnd(id: "reasoning-0", providerMetadata: nil),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "b", providerMetadata: nil),
            .reasoningStart(id: "reasoning-1", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-1", delta: "\nc", providerMetadata: nil),
            .reasoningEnd(id: "reasoning-1", providerMetadata: nil),
            .textDelta(id: "1", delta: "\nd", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }

    @Test("publishes a partial tag held at the end of a text part", arguments: [
        ("Use the <th", "Use the <th", nil),
        ("<think>a </th", nil, "a </th"),
    ] as [(String, String?, String?)])
    func streamPartialTagAtEnd(_ delta: String, _ text: String?, _ reasoning: String?) async throws {
        let output = try await streamThroughMiddleware(middleware(), textStream("1", [delta]))

        #expect(textDeltas(output) == text)
        #expect(reasoningDeltas(output) == reasoning)
    }

    @Test("extracts reasoning from overlapping text parts")
    func streamOverlappingTextParts() async throws {
        let output = try await streamThroughMiddleware(middleware(), [
            .textStart(id: "a", providerMetadata: nil),
            .textStart(id: "b", providerMetadata: nil),
            .textDelta(id: "a", delta: "<think>A", providerMetadata: nil),
            .textDelta(id: "b", delta: "<think>B", providerMetadata: nil),
            .textDelta(id: "a", delta: "1</think>Alpha.", providerMetadata: nil),
            .textDelta(id: "b", delta: "2</think>Beta.", providerMetadata: nil),
            .textEnd(id: "a", providerMetadata: nil),
            .textEnd(id: "b", providerMetadata: nil),
            middlewareTestFinish,
        ])

        #expect(output == [
            .reasoningStart(id: "reasoning-0", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-0", delta: "A", providerMetadata: nil),
            .reasoningStart(id: "reasoning-1", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-1", delta: "B", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-0", delta: "1", providerMetadata: nil),
            .reasoningEnd(id: "reasoning-0", providerMetadata: nil),
            .textStart(id: "a", providerMetadata: nil),
            .textDelta(id: "a", delta: "Alpha.", providerMetadata: nil),
            .reasoningDelta(id: "reasoning-1", delta: "2", providerMetadata: nil),
            .reasoningEnd(id: "reasoning-1", providerMetadata: nil),
            .textStart(id: "b", providerMetadata: nil),
            .textDelta(id: "b", delta: "Beta.", providerMetadata: nil),
            .textEnd(id: "a", providerMetadata: nil),
            .textEnd(id: "b", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }

    @Test("emits a start and end for empty <think></think> tags")
    func streamEmptyTags() async throws {
        let output = try await streamThroughMiddleware(
            middleware(),
            textStream("1", ["<think></think>", " This is the answer."])
        )

        #expect(output == [
            .reasoningStart(id: "reasoning-0", providerMetadata: nil),
            .reasoningEnd(id: "reasoning-0", providerMetadata: nil),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: " This is the answer.", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }

    @Test("forwards text without tags and a text part without deltas unchanged")
    func streamWithoutTags() async throws {
        let output = try await streamThroughMiddleware(middleware(), [
            .textStart(id: "1", providerMetadata: ["p": ["k": .string("v")]]),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .textStart(id: "2", providerMetadata: nil),
            .textEnd(id: "2", providerMetadata: nil),
            middlewareTestFinish,
        ])

        #expect(output == [
            .textStart(id: "1", providerMetadata: ["p": ["k": .string("v")]]),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .textStart(id: "2", providerMetadata: nil),
            .textEnd(id: "2", providerMetadata: nil),
            middlewareTestFinish,
        ])
    }
}
