import Foundation

public struct EventSourceParserStreamOptions {
    public enum ErrorMode {
        case ignore
        case terminate
        case custom((ParseError) -> Void)
    }

    public var onError: ErrorMode
    public var onRetry: ((Int) -> Void)?
    public var onComment: ((String) -> Void)?

    public init(onError: ErrorMode = .ignore, onRetry: ((Int) -> Void)? = nil, onComment: ((String) -> Void)? = nil) {
        self.onError = onError
        self.onRetry = onRetry
        self.onComment = onComment
    }
}

public struct EventSourceParserStream {
    /// Преобразует поток байтов (Data) в поток EventSourceMessage, используя EventSourceParser.
    public static func makeStream(
        from input: AsyncThrowingStream<Data, Error>,
        options: EventSourceParserStreamOptions = .init()
    ) -> AsyncThrowingStream<EventSourceMessage, Error> {
        AsyncThrowingStream { continuation in
            actor StopFlag { var value: Bool = false; func setTrue() { value = true }; func get() -> Bool { value } }
            let stopFlag = StopFlag()
            let parser = EventSourceParser(callbacks: ParserCallbacks(
                onEvent: { continuation.yield($0) },
                onError: { error in
                    switch options.onError {
                    case .ignore:
                        break
                    case .terminate:
                        // Mark stop and finish with error. Reader loop will observe stop flag and break.
                        Task { await stopFlag.setTrue() }
                        continuation.finish(throwing: error)
                    case .custom(let handler):
                        handler(error)
                    }
                },
                onRetry: { retry in
                    options.onRetry?(retry)
                },
                onComment: { comment in
                    options.onComment?(comment)
                }
            ))

            Task {
                do {
                    for try await chunk in input {
                        if await stopFlag.get() { break }
                        parser.feed(chunk)
                    }
                    if await !stopFlag.get() {
                        parser.reset(consume: true)
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
