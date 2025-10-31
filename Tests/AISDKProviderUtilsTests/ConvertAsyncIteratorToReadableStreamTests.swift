/**
 Tests for convertAsyncIteratorToReadableStream.
 */

import Testing
@testable import AISDKProviderUtils

@Suite("convertAsyncIteratorToReadableStream Tests")
struct ConvertAsyncIteratorToReadableStreamTests {
    private struct TestIterator: AsyncIteratorProtocol, Sendable {
        let values: [Int]
        var index: Int = 0

        mutating func next() async throws -> Int? {
            guard index < values.count else { return nil }
            let value = values[index]
            index += 1
            return value
        }
    }

    @Test("yields all values in order")
    func yieldsAllValues() async throws {
        let stream = convertAsyncIteratorToReadableStream(TestIterator(values: [1, 2, 3]))
        var collected: [Int] = []

        for try await value in stream {
            collected.append(value)
        }

        #expect(collected == [1, 2, 3])
    }

    private struct ThrowingIterator: AsyncIteratorProtocol, Sendable {
        var hasYielded = false

        struct TestError: Error, Sendable {}

        mutating func next() async throws -> Int? {
            if !hasYielded {
                hasYielded = true
                return 1
            }
            throw TestError()
        }
    }

    @Test("propagates iterator errors")
    func propagatesErrors() async throws {
        let stream = convertAsyncIteratorToReadableStream(ThrowingIterator())
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first == 1)

        await #expect(throws: ThrowingIterator.TestError.self) {
            _ = try await iterator.next()
        }
    }
}
