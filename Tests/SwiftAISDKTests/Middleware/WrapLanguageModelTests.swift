/**
 Tests for wrapLanguageModel function.

 Port of `@ai-sdk/ai/src/middleware/wrap-language-model.test.ts`.
 */

import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

// MARK: - Test Helpers

extension LanguageModelV3GenerateResult {
    /// Extract first text content for testing
    var firstText: String? {
        for item in content {
            if case .text(let part) = item { return part.text }
        }
        return nil
    }

    /// Create modified result with transformed text
    func withModifiedText(_ transform: (String) -> String) -> Self {
        guard let text = firstText else { return self }
        return LanguageModelV3GenerateResult(
            content: [.text(.init(text: transform(text)))],
            finishReason: finishReason,
            usage: usage,
            providerMetadata: providerMetadata,
            request: request,
            response: response,
            warnings: warnings
        )
    }
}

@Suite("wrapLanguageModel")
struct WrapLanguageModelTests {

    // MARK: - Model Property Tests

    @Suite("model property")
    struct ModelPropertyTests {

        @Test("should pass through by default")
        func passThrough() async throws {
            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(modelId: "test-model"),
                middleware: .single(LanguageModelV3Middleware())
            )

            #expect(wrappedModel.modelId == "test-model")
        }

        @Test("should use middleware overrideModelId if provided")
        func middlewareOverride() async throws {
            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(modelId: "test-model"),
                middleware: .single(LanguageModelV3Middleware(
                    overrideModelId: { _ in "override-model" }
                ))
            )

            #expect(wrappedModel.modelId == "override-model")
        }

        @Test("should use modelId parameter if provided")
        func parameterOverride() async throws {
            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(modelId: "test-model"),
                middleware: .single(LanguageModelV3Middleware()),
                modelId: "override-model"
            )

            #expect(wrappedModel.modelId == "override-model")
        }
    }

    // MARK: - Provider Property Tests

    @Suite("provider property")
    struct ProviderPropertyTests {

        @Test("should pass through by default")
        func passThrough() async throws {
            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(provider: "test-provider"),
                middleware: .single(LanguageModelV3Middleware())
            )

            #expect(wrappedModel.provider == "test-provider")
        }

        @Test("should use middleware overrideProvider if provided")
        func middlewareOverride() async throws {
            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(provider: "test-provider"),
                middleware: .single(LanguageModelV3Middleware(
                    overrideProvider: { _ in "override-provider" }
                ))
            )

            #expect(wrappedModel.provider == "override-provider")
        }

        @Test("should use providerId parameter if provided")
        func parameterOverride() async throws {
            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(provider: "test-provider"),
                middleware: .single(LanguageModelV3Middleware()),
                providerId: "override-provider"
            )

            #expect(wrappedModel.provider == "override-provider")
        }
    }

    // MARK: - Supported URLs Property Tests

    @Suite("supportedUrls property")
    struct SupportedUrlsPropertyTests {

        @Test("should pass through by default")
        func passThrough() async throws {
            let supportedUrls = try NSRegularExpression(pattern: "^https://.*$")
            let originalUrls = ["original/*": [supportedUrls]]

            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(
                    supportedUrls: .value(originalUrls)
                ),
                middleware: .single(LanguageModelV3Middleware())
            )

            let result = try await wrappedModel.supportedUrls
            #expect(result.keys.contains("original/*"))
            #expect(result["original/*"]?.count == 1)
        }

        @Test("should use middleware overrideSupportedUrls if provided")
        func middlewareOverride() async throws {
            let overrideRegex = try NSRegularExpression(pattern: "^https://.*$")
            let originalUrls = try ["original/*": [NSRegularExpression(pattern: "^https://.*$")]]

            let wrappedModel = wrapLanguageModel(
                model: MockLanguageModelV3(
                    supportedUrls: .value(originalUrls)
                ),
                middleware: .single(LanguageModelV3Middleware(
                    overrideSupportedUrls: { _ in
                        ["override/*": [overrideRegex]]
                    }
                ))
            )

            let result = try await wrappedModel.supportedUrls
            #expect(result.keys.contains("override/*"))
            #expect(!result.keys.contains("original/*"))
        }
    }

    // MARK: - transformParams Middleware Tests

    @Test("should call transformParams middleware for doGenerate")
    func transformParamsForGenerate() async throws {
        actor CallTracker {
            var called = false
            var capturedType: LanguageModelV3Middleware.OperationType?

            func markCalled(type: LanguageModelV3Middleware.OperationType) {
                called = true
                capturedType = type
            }

            func wasCalled() -> Bool { called }
            func getType() -> LanguageModelV3Middleware.OperationType? { capturedType }
        }

        let tracker = CallTracker()
        let mockModel = MockLanguageModelV3(
            doGenerate: .array([
                LanguageModelV3GenerateResult(
                    content: [],
                    finishReason: .stop,
                    usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 5)
                )
            ])
        )

        let wrappedModel = wrapLanguageModel(
            model: mockModel,
            middleware: .single(LanguageModelV3Middleware(
                transformParams: { type, params, _ in
                    await tracker.markCalled(type: type)
                    return params
                }
            ))
        )

        let options = LanguageModelV3CallOptions(
            prompt: [
                .user(
                    content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                    providerOptions: nil
                )
            ]
        )

        _ = try await wrappedModel.doGenerate(options: options)

        let called = await tracker.wasCalled()
        let type = await tracker.getType()

        #expect(called)
        #expect(type == .generate)
        #expect(mockModel.doGenerateCalls.count == 1)
    }

    @Test("should call transformParams middleware for doStream")
    func transformParamsForStream() async throws {
        actor CallTracker {
            var called = false
            var capturedType: LanguageModelV3Middleware.OperationType?

            func markCalled(type: LanguageModelV3Middleware.OperationType) {
                called = true
                capturedType = type
            }

            func wasCalled() -> Bool { called }
            func getType() -> LanguageModelV3Middleware.OperationType? { capturedType }
        }

        let tracker = CallTracker()
        let mockModel = MockLanguageModelV3(
            doStream: .array([
                LanguageModelV3StreamResult(
                    stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
                        continuation.finish()
                    }
                )
            ])
        )

        let wrappedModel = wrapLanguageModel(
            model: mockModel,
            middleware: .single(LanguageModelV3Middleware(
                transformParams: { type, params, _ in
                    await tracker.markCalled(type: type)
                    return params
                }
            ))
        )

        let options = LanguageModelV3CallOptions(
            prompt: [
                .user(
                    content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                    providerOptions: nil
                )
            ]
        )

        _ = try await wrappedModel.doStream(options: options)

        let called = await tracker.wasCalled()
        let type = await tracker.getType()

        #expect(called)
        #expect(type == .stream)
        #expect(mockModel.doStreamCalls.count == 1)
    }

    // MARK: - wrapGenerate Middleware Tests

    @Test("should call wrapGenerate middleware")
    func wrapGenerateMiddleware() async throws {
        actor CallTracker {
            var wrapGenerateCalled = false
            var doGenerateCalled = false

            func markWrapCalled() { wrapGenerateCalled = true }
            func markDoGenerateCalled() { doGenerateCalled = true }

            func getWrapCalled() -> Bool { wrapGenerateCalled }
            func getDoGenerateCalled() -> Bool { doGenerateCalled }
        }

        let tracker = CallTracker()
        let mockModel = MockLanguageModelV3(
            doGenerate: .function { _ in
                await tracker.markDoGenerateCalled()
                return LanguageModelV3GenerateResult(
                    content: [],
                    finishReason: .stop,
                    usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 5)
                )
            }
        )

        let wrappedModel = wrapLanguageModel(
            model: mockModel,
            middleware: .single(LanguageModelV3Middleware(
                wrapGenerate: { doGenerate, _, _, _ in
                    await tracker.markWrapCalled()
                    return try await doGenerate()
                }
            ))
        )

        let options = LanguageModelV3CallOptions(
            prompt: [
                .user(
                    content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                    providerOptions: nil
                )
            ]
        )

        _ = try await wrappedModel.doGenerate(options: options)

        let wrapCalled = await tracker.getWrapCalled()
        let doGenerateCalled = await tracker.getDoGenerateCalled()

        #expect(wrapCalled)
        #expect(doGenerateCalled)
    }

    // MARK: - wrapStream Middleware Tests

    @Test("should call wrapStream middleware")
    func wrapStreamMiddleware() async throws {
        actor CallTracker {
            var wrapStreamCalled = false
            var doStreamCalled = false

            func markWrapCalled() { wrapStreamCalled = true }
            func markDoStreamCalled() { doStreamCalled = true }

            func getWrapCalled() -> Bool { wrapStreamCalled }
            func getDoStreamCalled() -> Bool { doStreamCalled }
        }

        let tracker = CallTracker()
        let mockModel = MockLanguageModelV3(
            doStream: .function { _ in
                await tracker.markDoStreamCalled()
                return LanguageModelV3StreamResult(
                    stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
                        continuation.finish()
                    }
                )
            }
        )

        let wrappedModel = wrapLanguageModel(
            model: mockModel,
            middleware: .single(LanguageModelV3Middleware(
                wrapStream: { _, doStream, _, _ in
                    await tracker.markWrapCalled()
                    return try await doStream()
                }
            ))
        )

        let options = LanguageModelV3CallOptions(
            prompt: [
                .user(
                    content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                    providerOptions: nil
                )
            ]
        )

        _ = try await wrappedModel.doStream(options: options)

        let wrapCalled = await tracker.getWrapCalled()
        let doStreamCalled = await tracker.getDoStreamCalled()

        #expect(wrapCalled)
        #expect(doStreamCalled)
    }

    // MARK: - Multiple Middlewares Tests

    @Suite("multiple middlewares")
    struct MultipleMiddlewaresTests {

        @Test("should call multiple transformParams middlewares in sequence for doGenerate")
        func multipleTransformParamsGenerate() async throws {
            actor CallTracker {
                var call1 = false
                var call2 = false

                func markCall1() { call1 = true }
                func markCall2() { call2 = true }

                func getCall1() -> Bool { call1 }
                func getCall2() -> Bool { call2 }
            }

            let tracker = CallTracker()
            let mockModel = MockLanguageModelV3(
                doGenerate: .array([
                    LanguageModelV3GenerateResult(
                        content: [],
                        finishReason: .stop,
                        usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 5)
                    )
                ])
            )

            let wrappedModel = wrapLanguageModel(
                model: mockModel,
                middleware: .multiple([
                    LanguageModelV3Middleware(
                        transformParams: { type, params, _ in
                            await tracker.markCall1()
                            return params
                        }
                    ),
                    LanguageModelV3Middleware(
                        transformParams: { type, params, _ in
                            await tracker.markCall2()
                            return params
                        }
                    )
                ])
            )

            let options = LanguageModelV3CallOptions(
                prompt: [
                    .user(
                        content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                        providerOptions: nil
                    )
                ]
            )

            _ = try await wrappedModel.doGenerate(options: options)

            let call1 = await tracker.getCall1()
            let call2 = await tracker.getCall2()

            #expect(call1)
            #expect(call2)
        }

        @Test("should call multiple transformParams middlewares in sequence for doStream")
        func multipleTransformParamsStream() async throws {
            actor CallTracker {
                var call1 = false
                var call2 = false

                func markCall1() { call1 = true }
                func markCall2() { call2 = true }

                func getCall1() -> Bool { call1 }
                func getCall2() -> Bool { call2 }
            }

            let tracker = CallTracker()
            let mockModel = MockLanguageModelV3(
                doStream: .array([
                    LanguageModelV3StreamResult(
                        stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
                            continuation.finish()
                        }
                    )
                ])
            )

            let wrappedModel = wrapLanguageModel(
                model: mockModel,
                middleware: .multiple([
                    LanguageModelV3Middleware(
                        transformParams: { type, params, _ in
                            await tracker.markCall1()
                            return params
                        }
                    ),
                    LanguageModelV3Middleware(
                        transformParams: { type, params, _ in
                            await tracker.markCall2()
                            return params
                        }
                    )
                ])
            )

            let options = LanguageModelV3CallOptions(
                prompt: [
                    .user(
                        content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                        providerOptions: nil
                    )
                ]
            )

            _ = try await wrappedModel.doStream(options: options)

            let call1 = await tracker.getCall1()
            let call2 = await tracker.getCall2()

            #expect(call1)
            #expect(call2)
        }

        @Test("should chain multiple wrapGenerate middlewares in the correct order")
        func multipleWrapGenerate() async throws {
            let mockModel = MockLanguageModelV3(
                doGenerate: .function { _ in
                    LanguageModelV3GenerateResult(
                        content: [.text(.init(text: "final generate result"))],
                        finishReason: .stop,
                        usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 5)
                    )
                }
            )

            actor CallTracker {
                var call1 = false
                var call2 = false

                func markCall1() { call1 = true }
                func markCall2() { call2 = true }

                func getCall1() -> Bool { call1 }
                func getCall2() -> Bool { call2 }
            }

            let tracker = CallTracker()

            let wrappedModel = wrapLanguageModel(
                model: mockModel,
                middleware: .multiple([
                    LanguageModelV3Middleware(
                        wrapGenerate: { doGenerate, _, _, _ in
                            await tracker.markCall1()
                            let result = try await doGenerate()
                            return result.withModifiedText { text in
                                "wrapGenerate1(\(text))"
                            }
                        }
                    ),
                    LanguageModelV3Middleware(
                        wrapGenerate: { doGenerate, _, _, _ in
                            await tracker.markCall2()
                            let result = try await doGenerate()
                            return result.withModifiedText { text in
                                "wrapGenerate2(\(text))"
                            }
                        }
                    )
                ])
            )

            let options = LanguageModelV3CallOptions(
                prompt: [
                    .user(
                        content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                        providerOptions: nil
                    )
                ]
            )

            let result = try await wrappedModel.doGenerate(options: options)

            let call1 = await tracker.getCall1()
            let call2 = await tracker.getCall2()

            #expect(call1)
            #expect(call2)
            #expect(result.firstText == "wrapGenerate1(wrapGenerate2(final generate result))")
        }

        @Test("should chain multiple wrapStream middlewares in the correct order")
        func multipleWrapStream() async throws {
            let mockModel = MockLanguageModelV3(
                doStream: .function { _ in
                    LanguageModelV3StreamResult(
                        stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
                            continuation.finish()
                        }
                    )
                }
            )

            actor CallTracker {
                var call1 = false
                var call2 = false

                func markCall1() { call1 = true }
                func markCall2() { call2 = true }

                func getCall1() -> Bool { call1 }
                func getCall2() -> Bool { call2 }
            }

            let tracker = CallTracker()

            let wrappedModel = wrapLanguageModel(
                model: mockModel,
                middleware: .multiple([
                    LanguageModelV3Middleware(
                        wrapStream: { _, doStream, _, _ in
                            await tracker.markCall1()
                            return try await doStream()
                        }
                    ),
                    LanguageModelV3Middleware(
                        wrapStream: { _, doStream, _, _ in
                            await tracker.markCall2()
                            return try await doStream()
                        }
                    )
                ])
            )

            let options = LanguageModelV3CallOptions(
                prompt: [
                    .user(
                        content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                        providerOptions: nil
                    )
                ]
            )

            _ = try await wrappedModel.doStream(options: options)

            let call1 = await tracker.getCall1()
            let call2 = await tracker.getCall2()

            #expect(call1)
            #expect(call2)
        }
    }

    // MARK: - Context Binding Tests

    @Test("should support models that use 'this' context in supportedUrls")
    func supportedUrlsContextBinding() async throws {
        // Create a custom model that uses computed property for supportedUrls
        final class MockLanguageModelWithImageSupport: LanguageModelV3, @unchecked Sendable {
            let specificationVersion = "v3"
            let provider = "test-provider"
            let modelId = "test-model"

            var supportedUrlsAccessCount = 0

            let value: [String: [NSRegularExpression]]

            init() {
                self.value = try! ["image/*": [NSRegularExpression(pattern: "^https://.*$")]]
            }

            var supportedUrls: [String: [NSRegularExpression]] {
                get async throws {
                    supportedUrlsAccessCount += 1
                    return value
                }
            }

            func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
                fatalError("Not implemented")
            }

            func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
                fatalError("Not implemented")
            }
        }

        let model = MockLanguageModelWithImageSupport()

        let wrappedModel = wrapLanguageModel(
            model: model,
            middleware: .single(LanguageModelV3Middleware())
        )

        let urls = try await wrappedModel.supportedUrls
        #expect(urls.keys.contains("image/*"))
        #expect(model.supportedUrlsAccessCount == 1)
    }
}
