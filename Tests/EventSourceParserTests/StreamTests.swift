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
