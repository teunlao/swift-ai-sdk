/**
 Tests for smooth streaming algorithm.

 Port of `@ai-sdk/ai/src/generate-text/smooth-stream.test.ts`.

 Comprehensive test suite covering word/line/custom chunking, delay configuration,
 buffer flushing, and error handling.
 */

import Testing
import Foundation
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

// MARK: - Test Helpers

/// Convert array to AsyncSequence for testing.
struct ArrayAsyncSequence<Element: Sendable>: AsyncSequence, Sendable {
    typealias AsyncIterator = Iterator

    let array: [Element]

    struct Iterator: AsyncIteratorProtocol {
        var index = 0
        let array: [Element]

        mutating func next() async -> Element? {
            guard index < array.count else { return nil }
            let element = array[index]
            index += 1
            return element
        }
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(array: array)
    }
}

func convertArrayToAsyncStream<T: Sendable>(_ array: [T]) -> ArrayAsyncSequence<T> {
    ArrayAsyncSequence(array: array)
}

/// Event type for testing.
enum TestEvent: Sendable, Equatable {
    case part(String) // Simplified: just track text/type
    case delay(String)

    static func == (lhs: TestEvent, rhs: TestEvent) -> Bool {
        switch (lhs, rhs) {
        case (.part(let l), .part(let r)): return l == r
        case (.delay(let l), .delay(let r)): return l == r
        default: return false
        }
    }
}

/// Helper to consume stream and collect events.
actor EventCollector {
    private(set) var events: [TestEvent] = []

    func append(_ event: TestEvent) {
        events.append(event)
    }

    func getEvents() -> [TestEvent] {
        events
    }
}

/// Test delay function.
func makeTestDelayFunction(collector: EventCollector) -> @Sendable (Int?) async -> Void {
    { delayInMs in
        await collector.append(.delay("delay \(delayInMs.map { String($0) } ?? "nil")"))
    }
}

// MARK: - Test Suite

@Suite("SmoothStream Tests")
struct SmoothStreamTests {

    // MARK: - Word Chunking Tests

    @Test("Should combine partial words")
    func shouldCombinePartialWords() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello", providerMetadata: nil),
            .textDelta(id: "1", text: ", ", providerMetadata: nil),
            .textDelta(id: "1", text: "world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .mode(.word),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textStart: await collector.append(.part("text-start"))
            case .textEnd: await collector.append(.part("text-end"))
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            default: break
            }
        }

        let events = await collector.getEvents()

        #expect(events.contains(.part("text-start")))
        #expect(events.contains(.delay("delay 10")))
        #expect(events.contains(.part("text:Hello, ")))
        #expect(events.contains(.part("text:world!")))
        #expect(events.contains(.part("text-end")))
    }

    @Test("Should split larger text chunks")
    func shouldSplitLargerTextChunks() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello, World! This is an example text.", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .mode(.word),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            default: break
            }
        }

        let events = await collector.getEvents()

        // Should have multiple word chunks
        let textEvents = events.compactMap { ev -> String? in
            if case .part(let str) = ev, str.starts(with: "text:") { return str }
            return nil
        }

        #expect(textEvents.count > 3) // Multiple chunks created
    }

    @Test("Should send remaining buffer before non-text-delta")
    func shouldFlushBufferBeforeNonTextDelta() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "I will check the", providerMetadata: nil),
            .textDelta(id: "1", text: " weather", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .mode(.word),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            case .textEnd: await collector.append(.part("text-end"))
            default: break
            }
        }

        let events = await collector.getEvents()

        // Buffer "weather" should be flushed before text-end
        let lastTextIndex = events.lastIndex { ev in
            if case .part(let str) = ev, str.starts(with: "text:") { return true }
            return false
        }
        let textEndIndex = events.lastIndex { ev in
            if case .part(let str) = ev, str == "text-end" { return true }
            return false
        }

        if let lastText = lastTextIndex, let textEnd = textEndIndex {
            #expect(lastText < textEnd) // Text should come before text-end
        }
    }

    @Test("Doesn't return chunks with just spaces")
    func doesntReturnChunksWithJustSpaces() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: " ", providerMetadata: nil),
            .textDelta(id: "1", text: " ", providerMetadata: nil),
            .textDelta(id: "1", text: " ", providerMetadata: nil),
            .textDelta(id: "1", text: "foo", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .mode(.word),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            default: break
            }
        }

        let events = await collector.getEvents()

        // Should combine spaces with "foo"
        #expect(events.contains(.part("text:   foo")))
    }

    // MARK: - Line Chunking Tests

    @Test("Should split text by lines")
    func shouldSplitTextByLines() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "First line\nSecond line\nThird line\n", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .mode(.line),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            default: break
            }
        }

        let events = await collector.getEvents()

        // Should split by newlines
        #expect(events.contains(.part("text:First line\n")))
        #expect(events.contains(.part("text:Second line\n")))
    }

    @Test("Should handle text without line endings in line mode")
    func shouldHandleTextWithoutLineEndings() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Text without", providerMetadata: nil),
            .textDelta(id: "1", text: " any line", providerMetadata: nil),
            .textDelta(id: "1", text: " breaks", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .mode(.line),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            default: break
            }
        }

        let events = await collector.getEvents()

        // Should flush all text at end
        #expect(events.contains(.part("text:Text without any line breaks")))
    }

    // MARK: - Custom Regex Tests

    @Test("Should support custom regex chunking")
    func shouldSupportCustomRegexChunking() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello_, world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let regex = try NSRegularExpression(pattern: "_", options: [])

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .mode(.regex(regex)),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            default: break
            }
        }

        let events = await collector.getEvents()

        // Should split at "_"
        #expect(events.contains(.part("text:Hello_")))
        #expect(events.contains(.part("text:, world!")))
    }

    // MARK: - Custom Detector Tests

    @Test("Should support custom chunking callback")
    func shouldSupportCustomChunkingCallback() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "He_llo, ", providerMetadata: nil),
            .textDelta(id: "1", text: "w_orld!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let customDetector: ChunkDetector = { buffer in
            let regex = try? NSRegularExpression(pattern: "[^_]*_", options: [])
            let range = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
            guard let match = regex?.firstMatch(in: buffer, options: [], range: range) else {
                return nil
            }
            let matchRange = Range(match.range, in: buffer)!
            return String(buffer[matchRange])
        }

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 10,
            chunking: .detector(customDetector),
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await part in smoothed {
            switch part {
            case .textDelta(_, let text, _): await collector.append(.part("text:\(text)"))
            default: break
            }
        }

        let events = await collector.getEvents()

        #expect(events.contains(.part("text:He_")))
        #expect(events.contains(.part("text:llo, w_")))
        #expect(events.contains(.part("text:orld!")))
    }

    @Test("Throws empty match error")
    func throwsEmptyMatchError() async throws {
        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello, world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let emptyDetector: ChunkDetector = { _ in "" }

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: nil,
            chunking: .detector(emptyDetector)
        )

        await #expect(throws: Error.self) {
            for try await _ in smoothed {
                // Should throw
            }
        }
    }

    @Test("Throws match prefix error")
    func throwsMatchPrefixError() async throws {
        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello, world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let badDetector: ChunkDetector = { _ in "world" }

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: nil,
            chunking: .detector(badDetector)
        )

        await #expect(throws: Error.self) {
            for try await _ in smoothed {
                // Should throw
            }
        }
    }

    // MARK: - Delay Tests

    @Test("Should default to 10ms")
    func shouldDefaultTo10ms() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello, world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await _ in smoothed { }

        let events = await collector.getEvents()
        #expect(events.contains(.delay("delay 10")))
    }

    @Test("Should support different delay values")
    func shouldSupportDifferentDelayValues() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello, world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: 20,
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await _ in smoothed { }

        let events = await collector.getEvents()
        #expect(events.contains(.delay("delay 20")))
    }

    @Test("Should support nil delay")
    func shouldSupportNilDelay() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", text: "Hello, world!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            delayInMs: nil,
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        for try await _ in smoothed { }

        let events = await collector.getEvents()
        #expect(events.contains(.delay("delay nil")))
    }

    // MARK: - ID Change Tests

    @Test("Should handle text part ID changes")
    func shouldHandleTextPartIdChanges() async throws {
        let collector = EventCollector()
        let delay = makeTestDelayFunction(collector: collector)

        let input: [TextStreamPart] = [
            .textStart(id: "1", providerMetadata: nil),
            .textStart(id: "2", providerMetadata: nil),
            .textDelta(id: "1", text: "First ", providerMetadata: nil),
            .textDelta(id: "1", text: "text ", providerMetadata: nil),
            .textDelta(id: "2", text: "Second ", providerMetadata: nil),
            .textDelta(id: "2", text: "text ", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .textEnd(id: "2", providerMetadata: nil)
        ]

        let stream: ArrayAsyncSequence<TextStreamPart> = convertArrayToAsyncStream(input)
        let smoothed = try smoothStream(stream: stream, 
            _internal: SmoothStreamInternalOptions(delay: delay)
        )

        var id1Count = 0
        var id2Count = 0

        for try await part in smoothed {
            switch part {
            case .textDelta(let id, _, _):
                if id == "1" { id1Count += 1 }
                if id == "2" { id2Count += 1 }
            default: break
            }
        }

        #expect(id1Count > 0)
        #expect(id2Count > 0)
    }
}
