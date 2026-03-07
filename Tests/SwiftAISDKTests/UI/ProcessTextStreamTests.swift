import Foundation
import Testing
@testable import SwiftAISDK

@Suite("processTextStream")
struct ProcessTextStreamTests {
    @Test("should process stream chunks correctly")
    func processesStreamChunksCorrectly() async throws {
        let chunks = ["Hello", " ", "World"].map { Data($0.utf8) }
        let stream = makeByteStream(chunks)
        let captured = LockedTextParts()

        try await processTextStream(stream: stream) { chunk in
            await captured.append(chunk)
        }

        #expect(await captured.value() == ["Hello", " ", "World"])
    }

    @Test("should handle empty streams")
    func handlesEmptyStreams() async throws {
        let stream = makeByteStream([])
        let captured = LockedTextParts()

        try await processTextStream(stream: stream) { chunk in
            await captured.append(chunk)
        }

        #expect(await captured.value().isEmpty)
    }

    @Test("should preserve UTF-8 characters split across chunk boundaries")
    func preservesSplitUTF8Characters() async throws {
        let stream = makeByteStream([
            Data([0xF0, 0x9F]),
            Data([0x98, 0x80]),
            Data(" done".utf8)
        ])
        let captured = LockedTextParts()

        try await processTextStream(stream: stream) { chunk in
            await captured.append(chunk)
        }

        #expect(await captured.value() == ["😀", " done"])
    }
}

private actor LockedTextParts {
    private var chunks: [String] = []

    func append(_ chunk: String) {
        chunks.append(chunk)
    }

    func value() -> [String] {
        chunks
    }
}

private func makeByteStream(
    _ chunks: [Data]
) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}
