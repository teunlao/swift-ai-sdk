import Testing
@testable import EventSourceParser
import Foundation

@Test func eventSourceParserStream_basic() async throws {
    var fixture = ""
    for i in 0..<10 {
        fixture += "id: evt-\(i)\nevent: foo\ndata: Hello \(i)\n\n"
    }

    let bytes = fixture.data(using: .utf8)!
    let input = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(bytes)
        continuation.finish()
    }

    var received: [EventSourceMessage] = []
    for try await msg in EventSourceParserStream.makeStream(from: input) {
        received.append(msg)
    }

    #expect(received.count == 10)
    #expect(received.first?.id == "evt-0")
    #expect(received.first?.event == "foo")
    #expect(received.first?.data == "Hello 0")
    #expect(received.last?.id == "evt-9")
    #expect(received.last?.event == "foo")
    #expect(received.last?.data == "Hello 9")
}

@Test func eventSourceParserStream_terminateOnError() async {
    let invalid = "foo: bar\n"
    let input = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data(invalid.utf8))
        continuation.finish()
    }
    let options = EventSourceParserStreamOptions(onError: .terminate)

    do {
        for try await _ in EventSourceParserStream.makeStream(from: input, options: options) {
            #expect(Bool(false), "Should not yield events")
        }
        #expect(Bool(false), "Should throw")
    } catch {
        // expected termination
    }
}

@Test func eventSourceParserStream_customErrorHandler() async throws {
    var captured: [ParseError] = []
    let invalid = "foo: bar\n"
    let valid = "data: ok\n\n"
    let input = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data(invalid.utf8))
        continuation.yield(Data(valid.utf8))
        continuation.finish()
    }
    let options = EventSourceParserStreamOptions(onError: .custom { captured.append($0) })
    var received: [EventSourceMessage] = []
    for try await msg in EventSourceParserStream.makeStream(from: input, options: options) {
        received.append(msg)
    }
    #expect(!captured.isEmpty)
    #expect(received.first?.data == "ok")
}

// MARK: - feed(Data) UTF-8 chunk boundary handling (end-to-end)

@Test func eventSourceParserStream_asciiSplitChunks() async throws {
    // ASCII data split into many small chunks should work fine
    let event = "data: Hello World\n\n"
    let bytes = Data(event.utf8)

    // Yield one byte at a time
    let input = AsyncThrowingStream<Data, Error> { continuation in
        for byte in bytes {
            continuation.yield(Data([byte]))
        }
        continuation.finish()
    }

    var received: [EventSourceMessage] = []
    for try await msg in EventSourceParserStream.makeStream(from: input) {
        received.append(msg)
    }

    #expect(received.count == 1)
    #expect(received.first?.data == "Hello World")
}

@Test func eventSourceParserStream_splitMultibyteChunkLosesEvents() async throws {
    // Simulates what makeDataStream() does: yields Data chunks at arbitrary
    // byte boundaries. When the boundary falls inside a multi-byte UTF-8
    // character, the parser must carry over the incomplete bytes.
    let event1 = "data: {\"type\":\"content_block_delta\",\"index\":0}\n\n"
    let event2 = "data: {\"thinking\":\"The café serves résumés\"}\n\n"
    let event3 = "data: {\"type\":\"content_block_stop\"}\n\n"

    var allBytes = Data()
    allBytes.append(Data(event1.utf8))
    allBytes.append(Data(event2.utf8))
    allBytes.append(Data(event3.utf8))

    // "é" in "café" is C3 A9. Split between C3 and A9.
    let eAcuteUTF8 = Data([0xC3, 0xA9])
    guard let accentRange = allBytes.firstRange(of: eAcuteUTF8) else {
        Issue.record("Could not find accented character bytes")
        return
    }
    let splitPoint = accentRange.lowerBound + 1

    let chunk1 = Data(allBytes.prefix(splitPoint))
    let chunk2 = Data(allBytes.suffix(from: splitPoint))

    let input = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(chunk1)
        continuation.yield(chunk2)
        continuation.finish()
    }

    var received: [EventSourceMessage] = []
    for try await msg in EventSourceParserStream.makeStream(from: input) {
        received.append(msg)
    }

    #expect(received.count == 3, "All three events should be received despite multi-byte split")
    #expect(received[0].data == "{\"type\":\"content_block_delta\",\"index\":0}")
    #expect(received[1].data == "{\"thinking\":\"The café serves résumés\"}")
    #expect(received[2].data == "{\"type\":\"content_block_stop\"}")
}

@Test func eventSourceParserStream_microChunksWithMultibyte() async throws {
    // Feed the entire payload 3 bytes at a time -- guarantees many
    // multi-byte characters will be split across chunk boundaries
    var fixture = ""
    for i in 0..<3 {
        fixture += "data: msg\(i) 中文😀\n\n"
    }
    let bytes = Data(fixture.utf8)

    let chunkSize = 3
    let input = AsyncThrowingStream<Data, Error> { continuation in
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunkSize, bytes.count)
            continuation.yield(Data(bytes[offset..<end]))
            offset = end
        }
        continuation.finish()
    }

    var received: [EventSourceMessage] = []
    for try await msg in EventSourceParserStream.makeStream(from: input) {
        received.append(msg)
    }

    #expect(received.count == 3)
    for i in 0..<3 {
        #expect(received[i].data == "msg\(i) 中文😀")
    }
}
