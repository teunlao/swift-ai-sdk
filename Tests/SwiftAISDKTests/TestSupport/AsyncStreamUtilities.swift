import Foundation

func makeAsyncStream<Element: Sendable>(
    from elements: [Element]
) -> AsyncThrowingStream<Element, Error> {
    AsyncThrowingStream { continuation in
        for element in elements {
            continuation.yield(element)
        }
        continuation.finish()
    }
}

func collectStream<Element: Sendable>(
    _ stream: AsyncThrowingStream<Element, Error>
) async throws -> [Element] {
    var iterator = stream.makeAsyncIterator()
    var values: [Element] = []
    while let value = try await iterator.next() {
        values.append(value)
    }
    return values
}

