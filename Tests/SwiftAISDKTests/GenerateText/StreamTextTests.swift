/**
 StreamText – Edge Cases, Races & Flakes – Full Suite
 Uses: Swift Testing
 */

import Foundation
import Testing

@testable import AISDKProvider
@testable import SwiftAISDK

// MARK: - Common helpers

private enum TimeoutError: Error { case timeout }

@discardableResult
private func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    _ op: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timeout
        }
        let val = try await group.next()!
        group.cancelAll()
        return val
    }
}

private let testUsage = LanguageModelUsage(
    inputTokens: 3, outputTokens: 10, totalTokens: 13
)

private func makeStream(
    parts: [LanguageModelV3StreamPart],
    perPartDelayNs: UInt64? = nil
) -> AsyncThrowingStream<LanguageModelV3StreamPart, Error> {
    AsyncThrowingStream { continuation in
        Task {
            for p in parts {
                if let d = perPartDelayNs { try? await Task.sleep(nanoseconds: d) }
                continuation.yield(p)
            }
            continuation.finish()
        }
    }
}

private func makeModel(
    stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
) -> MockLanguageModelV3 {
    MockLanguageModelV3(
        doStream: .function { _ in
            LanguageModelV3StreamResult(
                stream: stream,
                request: nil,
                response: nil
            )
        }
    )
}

private func helloWorldParts(includeStreamStart: Bool = true) -> [LanguageModelV3StreamPart] {
    var out: [LanguageModelV3StreamPart] = []
    if includeStreamStart {
        out.append(.streamStart(warnings: []))
        out.append(
            .responseMetadata(
                id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)))
    }
    out.append(.textStart(id: "1", providerMetadata: nil))
    out.append(.textDelta(id: "1", delta: "Hello", providerMetadata: nil))
    out.append(.textDelta(id: "1", delta: ", ", providerMetadata: nil))
    out.append(.textDelta(id: "1", delta: "world!", providerMetadata: nil))
    out.append(.textEnd(id: "1", providerMetadata: nil))
    out.append(.finish(finishReason: .stop, usage: testUsage, providerMetadata: nil))
    return out
}

private func collectText(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var acc: [String] = []
    for try await s in stream { acc.append(s) }
    return acc
}

private func collectFull(_ stream: AsyncThrowingStream<TextStreamPart, Error>) async throws
    -> [TextStreamPart]
{
    var acc: [TextStreamPart] = []
    for try await p in stream { acc.append(p) }
    return acc
}

// MARK: - 1) Базовые текстовые сценарии

@Suite("StreamText – textStream basic")
struct StreamTextTextStreamBasic {

    @Test("sends text deltas")
    func sendsTextDeltas() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: ", ", providerMetadata: nil),
            .textDelta(id: "1", delta: "world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
        ]
        let model = makeModel(stream: makeStream(parts: parts))
        let result: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model), prompt: "test-input")

        let collected = try await withTimeout(2) { try await collectText(result.textStream) }
        #expect(collected == ["Hello", ", ", "world!"])
        #expect(try await result.finishReason == .stop)
    }

    @Test("filters empty text deltas")
    func filtersEmptyTextDeltas() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: "", providerMetadata: nil),
            .textDelta(id: "1", delta: ", ", providerMetadata: nil),
            .textDelta(id: "1", delta: "", providerMetadata: nil),
            .textDelta(id: "1", delta: "world!", providerMetadata: nil),
            .textDelta(id: "1", delta: "", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
        ]
        let model = makeModel(stream: makeStream(parts: parts))
        let result: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model), prompt: "test-input")

        let collected = try await withTimeout(2) { try await collectText(result.textStream) }
        #expect(collected == ["Hello", ", ", "world!"])
    }
}

// MARK: - 2) Порядок событий в fullStream

@Suite("StreamText – fullStream order & invariants")
struct StreamTextFullOrder {

    @Test("only finish from model still produces startStep/finishStep and finish")
    func finishOnlyProducesStep() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
        ]
        let model = makeModel(stream: makeStream(parts: parts))
        let res: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model), prompt: "x")

        let full = try await withTimeout(2) { try await collectFull(res.fullStream) }

        // Проверяем наличие ключевых маркеров
        #expect(full.contains { if case .start = $0 { true } else { false } })
        #expect(full.contains { if case .startStep = $0 { true } else { false } })
        #expect(full.contains { if case .finishStep = $0 { true } else { false } })
        #expect(full.contains { if case .finish = $0 { true } else { false } })

        #expect(try await res.finishReason == .stop)
        #expect(try await res.steps.count == 1)
    }

    @Test("delta without start -> emits .error and does not hang")
    func deltaWithoutStartEmitsError() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .textDelta(id: "1", delta: "dangling", providerMetadata: nil),
            .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
        ]
        let model = makeModel(stream: makeStream(parts: parts))
        let res: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model), prompt: "x")

        let full = try await withTimeout(2) { try await collectFull(res.fullStream) }
        #expect(full.contains { if case .error = $0 { true } else { false } })
        #expect(try await res.finishReason == .stop)
    }

    @Test("reasoning delta without start -> emits .error and does not hang")
    func reasoningDeltaWithoutStartEmitsError() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .reasoningDelta(id: "r1", delta: "why", providerMetadata: nil),
            .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
        ]
        let model = makeModel(stream: makeStream(parts: parts))
        let res: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model), prompt: "x")

        let full = try await withTimeout(2) { try await collectFull(res.fullStream) }
        #expect(full.contains { if case .error = $0 { true } else { false } })
        #expect(try await res.finishReason == .stop)
    }

    @Test("missing textEnd still finishes cleanly")
    func missingTextEndFinishes() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .textStart(id: "x", providerMetadata: nil),
            .textDelta(id: "x", delta: "incomplete", providerMetadata: nil),
            .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
        ]
        let model = makeModel(stream: makeStream(parts: parts))
        let res: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model), prompt: "x")

        let collected = try await withTimeout(2) { try await collectText(res.textStream) }
        #expect(collected == ["incomplete"])
        #expect(try await res.finishReason == .stop)
    }
}

// // MARK: - 3) Abort-сценарии

// @Suite("StreamText – abort")
// struct StreamTextAbort {

//     @Test("immediate abort produces no deltas")
//     func immediateAbort() async throws {
//         let model = makeModel(stream: makeStream(parts: helloWorldParts()))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model),
//             prompt: "x",
//             settings: CallSettings(abortSignal: { true })
//         )

//         let txt = try await withTimeout(2) { try await collectText(res.textStream) }
//         #expect(txt.isEmpty)
//     }

//     @Test("mid-stream abort does not hang")
//     func midStreamAbort() async throws {
//         final class AbortBox: @unchecked Sendable {
//             private let lock = NSLock()
//             private var _aborted = false

//             func setAborted() {
//                 lock.lock()
//                 defer { lock.unlock() }
//                 _aborted = true
//             }

//             func isAborted() -> Bool {
//                 lock.lock()
//                 defer { lock.unlock() }
//                 return _aborted
//             }
//         }

//         let box = AbortBox()
//         let parts = helloWorldParts()
//         let model = makeModel(stream: makeStream(parts: parts, perPartDelayNs: 15_000_000))  // 15ms/chunk

//         Task {
//             try? await Task.sleep(nanoseconds: 20_000_000)
//             box.setAborted()
//         }

//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x",
//             settings: CallSettings(abortSignal: { box.isAborted() })
//         )

//         // Количество дельт может быть 0..N, главное — отсутствие зависаний
//         _ = try await withTimeout(2) { try await collectText(res.textStream) }
//     }
// }

// // MARK: - 4) Конкурентные подписчики и back-pressure

// @Suite("StreamText – concurrency & back-pressure")
// struct StreamTextConcurrencyBackPressure {

//     @Test("two concurrent textStream subscribers receive identical deltas")
//     func twoConcurrentSubscribers() async throws {
//         let model = makeModel(stream: makeStream(parts: helloWorldParts()))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")

//         let (x, y) = try await withTimeout(2) {
//             async let a = collectText(res.textStream)
//             async let b = collectText(res.textStream)
//             return try await (a, b)
//         }
//         #expect(x == ["Hello", ", ", "world!"])
//         #expect(y == ["Hello", ", ", "world!"])
//     }

//     @Test("ten concurrent fullStream subscribers all finish")
//     func tenFullSubscribers() async throws {
//         let model = makeModel(stream: makeStream(parts: helloWorldParts()))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")

//         try await withTimeout(3) {
//             try await withThrowingTaskGroup(of: Void.self) { g in
//                 for _ in 0..<10 {
//                     g.addTask {
//                         _ = try await collectFull(res.fullStream)
//                     }
//                 }
//                 try await g.waitForAll()
//             }
//         }
//         #expect(try await res.finishReason == .stop)
//     }

//     @Test("late subscriber gets remainder and finishes")
//     func lateSubscriberGetsRemainder() async throws {
//         let model = makeModel(
//             stream: makeStream(parts: helloWorldParts(), perPartDelayNs: 5_000_000))  // 5ms
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")

//         let (a, b) = try await withTimeout(3) {
//             async let first = collectText(res.textStream)

//             // Второй запаздывает
//             try? await Task.sleep(nanoseconds: 12_000_000)
//             async let second = collectText(res.textStream)

//             return try await (first, second)
//         }
//         // Первый — полный набор; второй — остаток (может совпасть, если успел)
//         #expect(a == ["Hello", ", ", "world!"])
//         #expect(!b.isEmpty)
//         #expect(try await res.finishReason == .stop)
//     }

//     @Test("slow consumer does not block pipeline (unbounded buffers)")
//     func slowConsumer() async throws {
//         var parts: [LanguageModelV3StreamPart] = [.textStart(id: "1", providerMetadata: nil)]
//         for i in 0..<400 {
//             parts.append(.textDelta(id: "1", delta: "x\(i)", providerMetadata: nil))
//         }
//         parts.append(.textEnd(id: "1", providerMetadata: nil))
//         parts.append(.finish(finishReason: .stop, usage: testUsage, providerMetadata: nil))

//         let model = makeModel(stream: makeStream(parts: parts))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")

//         var cnt = 0
//         for try await _ in res.textStream {
//             cnt += 1
//             try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
//         }
//         #expect(cnt == 400)
//         #expect(try await res.finishReason == .stop)
//     }

//     @Test("no consumer: finishReason resolves and no hang")
//     func noConsumerFinishReasonResolves() async throws {
//         let model = makeModel(stream: makeStream(parts: helloWorldParts()))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")
//         let reason = try await withTimeout(2) { try await res.finishReason }
//         #expect(reason == .stop)
//     }
// }

// // MARK: - 5) includeRawChunks и partial-output stream

// @Suite("StreamText – raw & partial output")
// struct StreamTextRawAndPartial {

//     @Test("raw chunks are forwarded when includeRawChunks == true")
//     func forwardsRawWhenEnabled() async throws {
//         let parts: [LanguageModelV3StreamPart] = [
//             .raw(rawValue: ["kind": "telemetry", "v": 1]),
//             .textStart(id: "1", providerMetadata: nil),
//             .textDelta(id: "1", delta: "A", providerMetadata: nil),
//             .textEnd(id: "1", providerMetadata: nil),
//             .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
//         ]
//         let model = makeModel(stream: makeStream(parts: parts))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model),
//             prompt: "x",
//             includeRawChunks: true
//         )

//         let full = try await withTimeout(2) { try await collectFull(res.fullStream) }
//         #expect(full.contains { if case .raw = $0 { true } else { false } })
//         #expect(try await res.finishReason == .stop)
//     }

//     @Test("experimentalPartialOutputStream without spec throws NoOutputSpecifiedError")
//     func partialStreamThrowsWithoutSpec() async throws {
//         let model = makeModel(stream: makeStream(parts: helloWorldParts()))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")

//         await #expect(throws: NoOutputSpecifiedError.self) {
//             _ = try await withTimeout(2) {
//                 var any: [Never] = []
//                 for try await v in res.experimentalPartialOutputStream { any.append(v) }
//                 return ()
//             }
//         }
//     }
// }

// // MARK: - 6) Консистентность контента и метаданных

// @Suite("StreamText – content & metadata consistency")
// struct StreamTextContentConsistency {

//     @Test("two different text ids produce two text blocks in full stream")
//     func twoIdsTwoBlocks() async throws {
//         let parts: [LanguageModelV3StreamPart] = [
//             .textStart(id: "a", providerMetadata: nil),
//             .textDelta(id: "a", delta: "AA", providerMetadata: nil),
//             .textEnd(id: "a", providerMetadata: nil),
//             .textStart(id: "b", providerMetadata: nil),
//             .textDelta(id: "b", delta: "BB", providerMetadata: nil),
//             .textEnd(id: "b", providerMetadata: nil),
//             .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
//         ]
//         let model = makeModel(stream: makeStream(parts: parts))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")
//         let full = try await withTimeout(2) { try await collectFull(res.fullStream) }

//         let texts = full.compactMap { part -> (String, String?)? in
//             switch part {
//             case let .textStart(id, _): return (id, nil)
//             case let .textDelta(_, t, _): return ("delta", t)
//             case let .textEnd(id, _): return (id, nil)
//             default: return nil
//             }
//         }
//         // Никаких зависаний, события прошли
//         #expect(!texts.isEmpty)
//         #expect(try await res.finishReason == .stop)
//     }

//     @Test("sources and files are forwarded")
//     func sourcesAndFilesForwarded() async throws {
//         let fileData = LanguageModelV3File(
//             mediaType: "text/plain",
//             data: .base64(Data("X".utf8).base64EncodedString())
//         )
//         let parts: [LanguageModelV3StreamPart] = [
//             .file(fileData),
//             .source(.url(id: "s1", url: "https://example.com", title: "E", providerMetadata: nil)),
//             .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil),
//         ]
//         let model = makeModel(stream: makeStream(parts: parts))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")
//         let full = try await withTimeout(2) { try await collectFull(res.fullStream) }

//         #expect(full.contains { if case .file = $0 { true } else { false } })
//         #expect(full.contains { if case .source = $0 { true } else { false } })
//         #expect(try await res.finishReason == .stop)
//     }
// }

// // MARK: - 7) OnChunk не блокирует финализацию шага

// @Suite("StreamText – onChunk back-pressure")
// struct StreamTextOnChunkBP {

//     @Test("heavy onChunk does not prevent finishReason resolving")
//     func heavyOnChunk() async throws {
//         let parts = helloWorldParts()
//         let model = makeModel(stream: makeStream(parts: parts))
//         let start = Date()

//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model),
//             prompt: "x",
//             onChunk: { _ in
//                 // имитируем тяжёлый обработчик
//                 try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
//             }
//         )

//         let reason = try await withTimeout(3) { try await res.finishReason }
//         #expect(reason == .stop)
//         // просто sanity-check, что уложились в таймаут
//         #expect(Date().timeIntervalSince(start) < 3.0)
//     }
// }

// // MARK: - 8) Stress

// @Suite("StreamText – stress")
// struct StreamTextStress {

//     @Test("1000 deltas stream finishes and totals preserved")
//     func largeStreamFinishes() async throws {
//         var parts: [LanguageModelV3StreamPart] = [.streamStart(warnings: [])]
//         parts.append(.responseMetadata(id: "id-1", modelId: "mock-model-id", timestamp: Date()))
//         parts.append(.textStart(id: "1", providerMetadata: nil))
//         for i in 0..<1000 {
//             parts.append(.textDelta(id: "1", delta: "a\(i)", providerMetadata: nil))
//         }
//         parts.append(.textEnd(id: "1", providerMetadata: nil))
//         parts.append(.finish(finishReason: .stop, usage: testUsage, providerMetadata: nil))

//         let model = makeModel(stream: makeStream(parts: parts))
//         let res: DefaultStreamTextResult<Never, Never> = try streamText(
//             model: .v3(model), prompt: "x")

//         var c = 0
//         for try await _ in res.textStream { c += 1 }
//         #expect(c == 1000)
//         #expect(try await res.finishReason == .stop)
//         #expect(try await res.totalUsage.totalTokens == testUsage.totalTokens)
//     }
// }
