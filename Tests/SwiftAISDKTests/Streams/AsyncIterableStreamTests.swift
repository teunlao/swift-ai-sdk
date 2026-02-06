import Foundation
import Testing
@testable import SwiftAISDK

@Suite("AsyncIterableStream")
struct AsyncIterableStreamTests {
    @Test("finishes when source completes immediately (no init race hang)")
    func finishesWhenSourceCompletesImmediately() async throws {
        let stream: AsyncIterableStream<Int> = createAsyncIterableStream(
            source: ImmediateAsyncSequence([1, 2, 3])
        )

        let values = try await withTimeout(nanoseconds: 1_000_000_000) {
            try await collect(stream)
        }

        #expect(values == [1, 2, 3])
    }
}

// MARK: - Helpers

private struct ImmediateAsyncSequence<Element: Sendable>: AsyncSequence, Sendable {
    typealias AsyncIterator = Iterator

    private let elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(elements: elements)
    }

    struct Iterator: AsyncIteratorProtocol {
        var elements: [Element]

        mutating func next() async -> Element? {
            guard !elements.isEmpty else { return nil }
            return elements.removeFirst()
        }
    }
}

private struct TestTimeoutError: Error, CustomStringConvertible, Sendable {
    var description: String {
        "Test timed out"
    }
}

private func withTimeout<T: Sendable>(
    nanoseconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            throw TestTimeoutError()
        }

        guard let result = try await group.next() else {
            throw TestTimeoutError()
        }

        group.cancelAll()
        return result
    }
}

private func collect<S: AsyncSequence>(
    _ sequence: S
) async throws -> [S.Element] {
    var iterator = sequence.makeAsyncIterator()
    var values: [S.Element] = []
    while let value = try await iterator.next() {
        values.append(value)
    }
    return values
}

