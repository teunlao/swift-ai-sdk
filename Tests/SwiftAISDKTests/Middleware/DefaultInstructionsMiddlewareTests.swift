import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK

private func transform(
    _ middleware: LanguageModelV4Middleware,
    _ params: LanguageModelV4CallOptions
) async throws -> LanguageModelV4CallOptions {
    try await middleware.transformParams!(.generate, params, MockLanguageModelV4())
}

private let emptyResult = LanguageModelV4GenerateResult(
    content: [],
    finishReason: .init(unified: .stop),
    usage: middlewareTestUsage
)

@Suite("defaultInstructionsMiddleware")
struct DefaultInstructionsMiddlewareTests {
    @Test("prepends instruction messages in order with their provider options and keeps other parameters")
    func prepends() async throws {
        let stringResult = try await transform(
            defaultInstructionsMiddleware(instructions: "Default instructions"),
            LanguageModelV4CallOptions(prompt: middlewareTestPrompt, temperature: 0.5, reasoning: .low)
        )
        #expect(stringResult.prompt == [.system(content: "Default instructions", providerOptions: nil)] + middlewareTestPrompt)
        #expect(stringResult.temperature == 0.5)
        #expect(stringResult.reasoning == .low)

        let cache: ProviderOptions = ["anthropic": ["cacheControl": .object(["type": .string("ephemeral")])]]
        let messagesResult = try await transform(
            defaultInstructionsMiddleware(instructions: [
                SystemModelMessage(content: "First", providerOptions: cache),
                SystemModelMessage(content: "Second"),
            ]),
            LanguageModelV4CallOptions(prompt: middlewareTestPrompt)
        )
        #expect(messagesResult.prompt == [
            .system(content: "First", providerOptions: cache),
            .system(content: "Second", providerOptions: nil),
        ] + middlewareTestPrompt)
    }

    @Test("leaves a prompt holding a system message anywhere, or empty instructions, unchanged")
    func unchanged() async throws {
        let promptWithLaterSystem: LanguageModelV4Prompt = middlewareTestPrompt + [
            .system(content: "Call instructions", providerOptions: nil),
        ]
        let withSystem = try await transform(
            defaultInstructionsMiddleware(instructions: "Default instructions"),
            LanguageModelV4CallOptions(prompt: promptWithLaterSystem)
        )
        #expect(withSystem.prompt == promptWithLaterSystem)

        let emptyInstructions = try await transform(
            defaultInstructionsMiddleware(instructions: [SystemModelMessage]()),
            LanguageModelV4CallOptions(prompt: middlewareTestPrompt)
        )
        #expect(emptyInstructions.prompt == middlewareTestPrompt)
    }

    @Test("applies to generate and stream calls of a wrapped model and respects an earlier middleware's system message")
    func wrappedModel() async throws {
        let model = MockLanguageModelV4(
            doGenerate: .singleValue(emptyResult),
            doStream: .singleValue(LanguageModelV4StreamResult(stream: makeAsyncStream(from: [])))
        )
        let wrapped = wrapLanguageModel(model: model, middleware: defaultInstructionsMiddleware(instructions: "Default"))
        _ = try await wrapped.doGenerate(options: LanguageModelV4CallOptions(prompt: middlewareTestPrompt))
        _ = try await wrapped.doStream(options: LanguageModelV4CallOptions(prompt: middlewareTestPrompt))

        let expected: LanguageModelV4Prompt = [.system(content: "Default", providerOptions: nil)] + middlewareTestPrompt
        #expect(model.doGenerateCalls.map(\.prompt) == [expected])
        #expect(model.doStreamCalls.map(\.prompt) == [expected])

        let earlier = LanguageModelV4Middleware(transformParams: { _, params, _ in
            LanguageModelV4CallOptions(prompt: [.system(content: "Earlier", providerOptions: nil)] + params.prompt)
        })
        let chainedModel = MockLanguageModelV4(doGenerate: .singleValue(emptyResult))
        _ = try await wrapLanguageModel(
            model: chainedModel,
            middleware: [earlier, defaultInstructionsMiddleware(instructions: "Default")]
        ).doGenerate(options: LanguageModelV4CallOptions(prompt: middlewareTestPrompt))

        #expect(chainedModel.doGenerateCalls.map(\.prompt) == [
            [.system(content: "Earlier", providerOptions: nil)] + middlewareTestPrompt,
        ])
    }
}
