import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – event stream")
struct StreamTextEventsTests {
    private let usage = LanguageModelV3Usage(inputTokens: 2, outputTokens: 5, totalTokens: 7)

    private func makeSampleParts() -> [TextStreamPart] {
        [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .textStart(id: "A", providerMetadata: nil),
            .textDelta(id: "A", text: "Hel", providerMetadata: nil),
            .textDelta(id: "A", text: "lo", providerMetadata: nil),
            .textEnd(id: "A", providerMetadata: nil),
            .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: usage)
        ]
    }

    @Test("event stream emits expected sequence")
    func eventStreamEmitsExpectedSequence() async throws {
        let parts = makeSampleParts()
        let stream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let eventStream = makeStreamTextEventStream(from: stream)
        let events = try await convertReadableStreamToArray(eventStream)

        if let first = events.first {
            switch first {
            case .start: break
            default: Issue.record("expected start event")
            }
        } else {
            Issue.record("missing events")
        }
        #expect(events.contains { if case .textDelta(text: "Hel", _) = $0 { return true } else { return false } })
        #expect(events.contains { if case .finish(reason: .stop, rawFinishReason: _, usage: _) = $0 { return true } else { return false } })
    }

    @Test("event summary aggregates text and finish metadata")
    func eventSummaryAggregatesText() async throws {
        let parts = makeSampleParts()
        let stream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let eventStream = makeStreamTextEventStream(from: stream)
        let summary = try await summarizeStreamTextEvents(eventStream)

        #expect(summary.text == "Hello")
        #expect(summary.finishReason == .stop)
        #expect(summary.usage?.totalTokens == usage.totalTokens)
        #expect(!summary.aborted)
    }

    @Test("event summary flags abort")
    func eventSummaryFlagsAbort() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .abort(reason: nil)
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let eventStream = makeStreamTextEventStream(from: stream)
        let summary = try await summarizeStreamTextEvents(eventStream)
        #expect(summary.aborted)
        #expect(summary.finishReason == nil)
    }
}
