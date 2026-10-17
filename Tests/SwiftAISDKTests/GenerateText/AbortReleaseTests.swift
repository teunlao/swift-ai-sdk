import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

/// Holds awaiters that ignore task cancellation until released.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() { lock.withLock { value = true } }
}

private final class Outcome<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var done = false

    func install(_ continuation: CheckedContinuation<T?, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(_ value: T?) {
        let continuation: CheckedContinuation<T?, Never>? = lock.withLock {
            guard !done else { return nil }
            done = true
            return self.continuation
        }
        continuation?.resume(returning: value)
    }
}

/// The operation's result, or nil when it is still running after `seconds`; the operation is not awaited past that.
private func within<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async -> T
) async -> T? {
    let outcome = Outcome<T>()
    return await withCheckedContinuation { continuation in
        outcome.install(continuation)
        Task { outcome.resume(await operation()) }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            outcome.resume(nil)
        }
    }
}

@Suite("Abort releases waits")
struct AbortReleaseTests {
    private let usage = LanguageModelV4Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))

    @Test("an abort ends fullStream while the provider read ignores cancellation")
    func abortReleasesUncooperativeProviderRead() async throws {
        let gate = Gate()
        defer { gate.open() }
        let aborted = Flag()
        let parts: [LanguageModelV4StreamPart] = [
            .streamStart(warnings: []),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "hello", providerMetadata: nil)
        ]
        let cursor = Cursor()
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(unfolding: {
            let index = cursor.next()
            if index < parts.count { return parts[index] }
            aborted.set()
            await gate.wait()
            return nil
        })
        let model = MockLanguageModelV4(doStream: .singleValue(LanguageModelV4StreamResult(stream: stream)))

        let result = try streamText(
            model: model,
            prompt: "go",
            settings: CallSettings(abortSignal: { aborted.isSet })
        )

        let parts_ = await within(seconds: 5) {
            (try? await convertReadableStreamToArray(result.fullStream)) ?? []
        }

        guard let streamed = parts_ else {
            Issue.record("fullStream did not end after the abort")
            return
        }
        guard case .abort? = streamed.last else {
            Issue.record("Expected the stream to end with an abort part, got \(String(describing: streamed.last))")
            return
        }
    }

    @Test("a stream retry starts after the failed attempt's provider stream ended")
    func retryEndsFailedAttempt() async throws {
        let firstEnded = Flag()
        let endedBeforeRetry = Flag()
        let calls = Cursor()
        let usage = self.usage
        let model = MockLanguageModelV4(doStream: .function { _ in
            if calls.next() == 0 {
                return LanguageModelV4StreamResult(stream: AsyncThrowingStream { continuation in
                    continuation.onTermination = { _ in firstEnded.set() }
                    continuation.yield(.streamStart(warnings: []))
                    continuation.yield(.error(error: .value(.string("overloaded"))))
                })
            }
            if firstEnded.isSet { endedBeforeRetry.set() }
            return LanguageModelV4StreamResult(stream: AsyncThrowingStream { continuation in
                continuation.yield(.streamStart(warnings: []))
                continuation.yield(.textStart(id: "1", providerMetadata: nil))
                continuation.yield(.textDelta(id: "1", delta: "ok", providerMetadata: nil))
                continuation.yield(.textEnd(id: "1", providerMetadata: nil))
                continuation.yield(.finish(
                    finishReason: LanguageModelV4FinishReason(unified: .stop),
                    usage: usage,
                    providerMetadata: nil
                ))
                continuation.finish()
            })
        })

        let result = try streamText(model: model, prompt: "go", streamRetries: 1)

        #expect(try await result.text == "ok")
        #expect(endedBeforeRetry.isSet)
    }

    @Test("an abort ends generateText while repairToolCall ignores it")
    func abortReleasesUncooperativeRepair() async throws {
        let gate = Gate()
        defer { gate.open() }
        let aborted = Flag()
        let model = MockLanguageModelV4(doGenerate: .singleValue(LanguageModelV4GenerateResult(
            content: [.toolCall(LanguageModelV4ToolCall(toolCallId: "call-1", toolName: "missing", input: "{}"))],
            finishReason: LanguageModelV4FinishReason(unified: .toolCalls),
            usage: usage
        )))
        let tools: ToolSet = ["present": tool(
            inputSchema: FlexibleSchema(jsonSchema(.object(["type": .string("object")]))),
            execute: { _, _ in .value(.null) }
        )]

        let outcome = await within(seconds: 5) { () -> String in
            do {
                _ = try await generateText(
                    model: model,
                    tools: tools,
                    prompt: "go",
                    repairToolCall: { _ in
                        aborted.set()
                        await gate.wait()
                        return nil
                    },
                    settings: CallSettings(abortSignal: { aborted.isSet })
                )
                return "finished"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "failed: \(error)"
            }
        }

        #expect(outcome == "cancelled")
    }

    @Test("an aborted call does not download its prompt files")
    func abortReachesPromptDownload() async throws {
        let model = MockLanguageModelV4(
            doGenerate: .singleValue(LanguageModelV4GenerateResult(
                content: [.text(LanguageModelV4Text(text: "ok"))],
                finishReason: LanguageModelV4FinishReason(unified: .stop),
                usage: usage
            ))
        )

        do {
            _ = try await generateText(
                model: model,
                messages: [.user(UserModelMessage(content: .parts([
                    .file(FilePart(data: .url(URL(string: "https://example.invalid/report.pdf")!), mediaType: "application/pdf"))
                ])))],
                settings: CallSettings(abortSignal: { true })
            )
            Issue.record("Expected the aborted call to fail")
        } catch let error as DownloadError {
            #expect(error.cause is CancellationError)
        }
        #expect(model.doGenerateCalls.isEmpty)
    }
}

private final class Cursor: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0

    func next() -> Int {
        lock.withLock {
            defer { index += 1 }
            return index
        }
    }
}
