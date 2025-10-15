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

func consumeStream<Element: Sendable>(
    stream: AsyncThrowingStream<Element, Error>
) async {
    var iterator = stream.makeAsyncIterator()
    while let _ = try? await iterator.next() {
        // Just drain the stream
    }
}

