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
