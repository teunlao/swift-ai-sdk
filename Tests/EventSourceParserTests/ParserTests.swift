import Testing
import Foundation
@testable import EventSourceParser

private final class Collector {
    var events: [EventSourceMessage] = []
    var retries: [Int] = []
    var comments: [String] = []
    var errors: [ParseError] = []
    var rawEvents: [EventSourceMessage] { events }
    func callbacks() -> ParserCallbacks {
        ParserCallbacks(
            onEvent: { [weak self] in self?.events.append($0) },
            onError: { [weak self] in self?.errors.append($0) },
            onRetry: { [weak self] in self?.retries.append($0) },
            onComment: { [weak self] in self?.comments.append($0) }
        )
    }
}

@Test func parser_basicUnnamedEvents() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    var s = ""
    for i in 0..<5 { s += "data: \(i)\n\n" }
    s += "event: done\ndata: ✔\n\n"
    p.feed(s)
    #expect(c.events.count == 6)
    #expect(c.events.first == EventSourceMessage(id: nil, event: nil, data: "0"))
    #expect(c.events.last == EventSourceMessage(id: nil, event: "done", data: "✔"))
}

@Test func parser_timeEvent() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    let lines = (0..<3).map { _ in "event: time\ndata: 2025-01-01T00:00:00.000Z\n\n" }.joined()
    p.feed(lines)
    #expect(c.events.count == 3)
    #expect(c.events[0].event == "time")
}

@Test func parser_chunkedFeed() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("data: hel")
    p.feed("lo\n\n")
    #expect(c.events.count == 1)
    #expect(c.events[0].data == "hello")
}

@Test func parser_identifiedWithRetry() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("retry: 50\n\n")
    p.feed("id: 1337\nevent: tick\ndata: 1337\n\n")
    p.feed("retry: 50\n\n")
    p.feed("id: 1338\nevent: tick\ndata: 1338\n\n")
    #expect(c.retries == [50, 50])
    #expect(c.events.map { $0.id } == ["1337", "1338"])
    #expect(c.events.map { $0.event } == ["tick", "tick"])
}

@Test func parser_comments() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed(": hb\ndata: data\n\n")
    #expect(c.comments.last == "hb")  // ": " removes both colon and space
    #expect(c.events.count == 1)
    #expect(c.events[0].data == "data")
}

@Test func parser_multiLineData() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("event: stock\ndata: YHOO\ndata: +2\ndata: 10\n\n")
    #expect(c.events.count == 1)
    #expect(c.events[0].event == "stock")
    #expect(c.events[0].data == "YHOO\n+2\n10")
}

@Test func parser_BOMHandling() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    let bom = String(UnicodeScalar(0xFEFF)!)
    p.feed(bom + "data: bomful 1\n\n")
    p.feed("data: bomless 2\n\n")
    #expect(c.events[0].data == "bomful 1")
    #expect(c.events[1].data == "bomless 2")
}

@Test func parser_invalidBOM_multiplePlaces() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    let bom = String(UnicodeScalar(0xFEFF)!)
    p.feed(bom + "data: bomful 1\n\n")
    p.feed(bom + "data: bomful 2\n\n")
    p.feed("data: bomless 3\n\n")
    // Expect only 'bomless 3' due to non-anchored BOM being treated as part of field name
    #expect(c.events.count == 2)
    #expect(c.events[0].data == "bomful 1")
    #expect(c.events[1].data == "bomless 3")
    #expect(c.errors.count == 1)
}

@Test func parser_crSeparatedChunksSameEvent() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("data: A\r\n")
    p.feed("data: B\r")
    p.feed("\n")
    p.feed("data: C\r\n")
    p.feed("\n")
    #expect(c.events.count == 1)
    #expect(c.events[0].data == "A\nB\nC")
}

@Test func parser_asciiOnlyRetry() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("retry: １２３\n\n") // full-width digits — not ASCII
    #expect(c.errors.count == 1)
    #expect(c.events.isEmpty)
}

@Test func parser_CR_LF_CRLF() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    // CR only
    p.feed("data: dog\r")
    p.feed("data: bark\r\r")
    // CRLF
    p.feed("data: sheep\r\n")
    p.feed("data: bleat\r\n\r\n")
    // LF
    p.feed("data: horse\n")
    p.feed("data: neigh\n\n")
    #expect(c.events.count == 3)
    #expect(c.events[0].data == "dog\nbark")
    #expect(c.events[1].data == "sheep\nbleat")
    #expect(c.events[2].data == "horse\nneigh")
}

@Test func parser_invalidRetry_and_unknownField_errors() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("retry: abc\nfoo: bar\n\n")
    #expect(c.errors.count == 2)
    if case .invalidRetry(let v, _) = c.errors[0].kind { #expect(v == "abc") } else { #expect(Bool(false)) }
    if case .unknownField(let f, _, _) = c.errors[1].kind { #expect(f == "foo") } else { #expect(Bool(false)) }
}

@Test func parser_invalidRetryFixture() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("retry:1000\n")
    p.feed("retry:2000x\n")
    p.feed("data:x\n\n")
    #expect(c.retries == [1000])
    #expect(c.errors.count == 1)
    if case .invalidRetry(let v, _) = c.errors[0].kind { #expect(v == "2000x") }
    #expect(c.events.last?.data == "x")
}

@Test func parser_timeEventChunked() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    for _ in 0..<5 {
        p.feed("id: \(UUID().uuidString)\n")
        p.feed("event: time\n")
        p.feed("data: 2025-01-01T00:00:00.000Z\n")
        p.feed("\n")
    }
    #expect(c.events.count == 5)
    #expect(c.events.allSatisfy { $0.event == "time" })
}

@Test func parser_multibyteEvents() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("id: 0\ndata: 我現在都看實況不玩遊戲 😀😃\n\n")
    p.feed("id: 1\ndata: こんにちは 世界 🌏\n\n")
    #expect(c.events.count == 2)
    #expect(c.events[0].data.contains("😀"))
    #expect(c.events[1].data.contains("🌏"))
}

@Test func parser_multibyteEmptyLine() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("\n\n\n\nid: 1\ndata: 我現在都看實況不玩遊戲\n\n")
    #expect(c.events.first?.id == "1")
    #expect(c.events.first?.data == "我現在都看實況不玩遊戲")
}

@Test func parser_leadingBOM() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    let bom = String(UnicodeScalar(0xFEFF)!)
    p.feed(bom + "data: bomful 1\n\n")
    p.feed("data: bomless 2\n\n")
    p.feed("event: done\ndata: ✔\n\n")
    #expect(c.events[0].data == "bomful 1")
    #expect(c.events[1].data == "bomless 2")
    #expect(c.events.last?.data == "✔")
}

@Test func parser_multiBom() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    let bom = String(UnicodeScalar(0xFEFF)!)
    p.feed(bom + "data: bomful 1\n\n")
    p.feed(bom + "data: bomful 2\n\n")
    p.feed("data: bomless 3\n\n")
    p.feed("event: done\ndata: ✔\n\n")
    #expect(c.events[0].data == "bomful 1")
    #expect(c.events[1].data == "bomless 3")
    #expect(c.events.count == 3)
}

@Test func parser_heartbeatsComments() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    for char in 65..<70 { // A..E
        p.feed(": ♥\n")
        p.feed("data: \(String(UnicodeScalar(char)!))\n\n")
    }
    p.feed("event: done\ndata: ✔\n\n")
    #expect(c.comments.count == 5)
    #expect(c.comments.last == "♥")  // ": " removes both colon and space
    for i in 0..<5 {
        #expect(c.events[i].data == String(UnicodeScalar(65 + i)!))
    }
    #expect(c.events.last?.data == "✔")
}

@Test func parser_unknownFieldsStream() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("data:abc\n data\ndata\nfoobar:xxx\njustsometext\n:thisisacommentyay\ndata:123\n\n")
    #expect(c.errors.count >= 2) // unknown field & missing colon
    #expect(c.events.last?.data == "abc\n\n123")
}

@Test func parser_emptyEvents() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("event:\ndata: Hello 1\n\n")
    p.feed("event:\n\n")
    p.feed("event: done\ndata: ✔\n\n")
    #expect(c.events[0].event == nil)
    #expect(c.events[0].data == "Hello 1")
    #expect(c.events[1].event == "done")
}

@Test func parser_emptyRetryChain() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("id:1\nretry:500\ndata:🥌\n\n")
    p.feed("id:2\nretry:\ndata:🧹\n\n")
    p.feed("id:3\ndata:✅\n\n")
    #expect(c.retries.first == 500)
    #expect(c.errors.contains { error in
        if case .invalidRetry(let value, _) = error.kind, value.isEmpty { return true }
        return false
    })
    #expect(c.events.last?.data == "✅")
}

@Test func parser_dataFieldParsing() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("data:\n\n")
    p.feed("data\ndata\n\n")
    p.feed("data:test\n\n")
    #expect(c.events.count == 3)
    #expect(c.events[0].data == "")
    #expect(c.events[1].data == "\n")
    #expect(c.events[2].data == "test")
}

@Test func parser_resetConsumeBehavior() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    let invalid = "{\"error\":\"Internal Server Error\",\"message\":\"fail\"}"
    p.feed(invalid)
    p.reset(consume: false)
    #expect(c.errors.isEmpty)
    p.feed(invalid)
    p.reset(consume: true)
    #expect(!c.errors.isEmpty)
}

@Test func parser_invalidStreamWithNewline() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed("{\"error\":\"Internal\"}\n")
    #expect(!c.errors.isEmpty)
}

// MARK: - feed(Data) UTF-8 chunk boundary handling

@Test func parser_feedData_asciiOnlyChunks() {
    // Pure ASCII should always work regardless of split position
    let event = "data: Hello World\n\n"
    let bytes = Data(event.utf8)

    // Split at every possible position
    for splitPoint in 1..<bytes.count {
        let c = Collector()
        let p = EventSourceParser(callbacks: c.callbacks())
        p.feed(Data(bytes.prefix(splitPoint)))
        p.feed(Data(bytes.suffix(from: splitPoint)))
        #expect(c.events.count == 1, "ASCII split at \(splitPoint) should produce 1 event")
        #expect(c.events.first?.data == "Hello World")
    }
}

@Test func parser_feedData_emptyChunks() {
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())

    // Empty chunks before, between, and after real data
    p.feed(Data())
    p.feed(Data("data: ok\n\n".utf8))
    p.feed(Data())

    #expect(c.events.count == 1)
    #expect(c.events.first?.data == "ok")
}

@Test func parser_feedData_split2ByteChar() {
    // "é" is C3 A9 (2 bytes). Split after the lead byte.
    let event = "data: café\n\n"
    let bytes = Data(event.utf8)

    let eAcuteUTF8 = Data([0xC3, 0xA9])
    guard let range = bytes.firstRange(of: eAcuteUTF8) else {
        Issue.record("Could not find é bytes")
        return
    }
    let splitPoint = range.lowerBound + 1

    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed(Data(bytes.prefix(splitPoint)))
    p.feed(Data(bytes.suffix(from: splitPoint)))

    #expect(c.events.count == 1)
    #expect(c.events.first?.data == "café")
}

@Test func parser_feedData_split3ByteChar() {
    // "中" is E4 B8 AD (3 bytes). Test split at each internal position.
    let event = "data: 中\n\n"
    let bytes = Data(event.utf8)

    let charUTF8 = Data([0xE4, 0xB8, 0xAD])
    guard let range = bytes.firstRange(of: charUTF8) else {
        Issue.record("Could not find 中 bytes")
        return
    }

    // Split after 1 byte (E4 | B8 AD) and after 2 bytes (E4 B8 | AD)
    for offset in 1...2 {
        let splitPoint = range.lowerBound + offset
        let c = Collector()
        let p = EventSourceParser(callbacks: c.callbacks())
        p.feed(Data(bytes.prefix(splitPoint)))
        p.feed(Data(bytes.suffix(from: splitPoint)))
        #expect(c.events.count == 1, "3-byte char split at offset \(offset) should produce 1 event")
        #expect(c.events.first?.data == "中")
    }
}

@Test func parser_feedData_split4ByteChar() {
    // "😀" is F0 9F 98 80 (4 bytes). Test split at each internal position.
    let event = "data: 😀\n\n"
    let bytes = Data(event.utf8)

    let charUTF8 = Data([0xF0, 0x9F, 0x98, 0x80])
    guard let range = bytes.firstRange(of: charUTF8) else {
        Issue.record("Could not find 😀 bytes")
        return
    }

    for offset in 1...3 {
        let splitPoint = range.lowerBound + offset
        let c = Collector()
        let p = EventSourceParser(callbacks: c.callbacks())
        p.feed(Data(bytes.prefix(splitPoint)))
        p.feed(Data(bytes.suffix(from: splitPoint)))
        #expect(c.events.count == 1, "4-byte char split at offset \(offset) should produce 1 event")
        #expect(c.events.first?.data == "😀")
    }
}

@Test func parser_feedData_4ByteCharFedByteByByte() {
    // Feed each byte of a 4-byte character as a separate Data chunk.
    // pendingBytes must accumulate across all 4 calls.
    let event = "data: X😀Y\n\n"
    let bytes = Array(event.utf8)

    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    for byte in bytes {
        p.feed(Data([byte]))
    }

    #expect(c.events.count == 1)
    #expect(c.events.first?.data == "X😀Y")
}

@Test func parser_feedData_consecutiveMultibyteChars() {
    // Two adjacent 4-byte emojis with the split falling between the
    // trailing bytes of the first and the leading byte of the second
    let event = "data: 🎉🎊\n\n"
    let bytes = Data(event.utf8)

    // 🎉 = F0 9F 8E 89, 🎊 = F0 9F 8E 8A
    // Split inside the first emoji after 2 bytes
    let firstEmoji = Data([0xF0, 0x9F, 0x8E, 0x89])
    guard let range = bytes.firstRange(of: firstEmoji) else {
        Issue.record("Could not find 🎉 bytes")
        return
    }
    let splitPoint = range.lowerBound + 2

    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed(Data(bytes.prefix(splitPoint)))
    p.feed(Data(bytes.suffix(from: splitPoint)))

    #expect(c.events.count == 1)
    #expect(c.events.first?.data == "🎉🎊")
}

@Test func parser_feedData_splitMultibyteCorruptsAdjacentEvents() {
    // Simulates the real failure mode: a dropped chunk merges fragments
    // of two different SSE events, producing garbled JSON
    let event1 = "data: {\"type\":\"content_block_delta\",\"index\":0}\n\n"
    let event2 = "data: {\"type\":\"thinking_delta\",\"thinking\":\"café résumé\"}\n\n"
    let event3 = "data: {\"type\":\"content_block_stop\"}\n\n"

    var allBytes = Data()
    allBytes.append(Data(event1.utf8))
    allBytes.append(Data(event2.utf8))
    allBytes.append(Data(event3.utf8))

    // "é" in "café" is C3 A9 in UTF-8 (2 bytes). Split inside it.
    let eAcuteUTF8 = Data([0xC3, 0xA9])
    guard let accentRange = allBytes.firstRange(of: eAcuteUTF8) else {
        Issue.record("Could not find accented character bytes")
        return
    }
    let splitPoint = accentRange.lowerBound + 1

    let chunk1 = Data(allBytes.prefix(splitPoint))
    let chunk2 = Data(allBytes.suffix(from: splitPoint))

    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())
    p.feed(chunk1)
    p.feed(chunk2)

    #expect(c.events.count == 3, "All events should survive a chunk split inside a multi-byte character")
    #expect(c.events[0].data == "{\"type\":\"content_block_delta\",\"index\":0}")
    #expect(c.events[1].data == "{\"type\":\"thinking_delta\",\"thinking\":\"café résumé\"}")
    #expect(c.events[2].data == "{\"type\":\"content_block_stop\"}")
}

@Test func parser_feedData_resetClearsPendingBytes() {
    // Feed an incomplete multi-byte sequence, then reset. The leftover
    // bytes should be discarded so the next feed starts clean.
    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())

    // First byte of "é" (C3) without the continuation byte
    p.feed(Data([0xC3]))
    p.reset(consume: false)

    // New event after reset should work normally
    p.feed(Data("data: clean\n\n".utf8))
    #expect(c.events.count == 1)
    #expect(c.events.first?.data == "clean")
}

@Test func parser_feedData_multipleEventsSpanningManySplits() {
    // 5 events with multi-byte content, fed in 3-byte micro-chunks
    var fixture = ""
    for i in 0..<5 {
        fixture += "data: msg\(i) \u{00E9}\u{4E2D}\u{1F600}\n\n"
    }
    let bytes = Data(fixture.utf8)

    let c = Collector()
    let p = EventSourceParser(callbacks: c.callbacks())

    let chunkSize = 3
    var offset = 0
    while offset < bytes.count {
        let end = min(offset + chunkSize, bytes.count)
        p.feed(Data(bytes[offset..<end]))
        offset = end
    }

    #expect(c.events.count == 5)
    for i in 0..<5 {
        #expect(c.events[i].data == "msg\(i) \u{00E9}\u{4E2D}\u{1F600}")
    }
}
