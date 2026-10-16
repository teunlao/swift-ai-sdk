/// Pipes `source` through `transform`, the Swift counterpart of upstream
/// `stream.pipeThrough(new TransformStream({ transform }))`.
///
/// One task owns the transform and its state: it reads `source` in order and
/// yields each chunk's output before reading the next. A source error ends the
/// stream with that error; the consumer cancelling the stream cancels the task.
func pipeMiddlewareStream<Part: Sendable>(
    _ source: AsyncThrowingStream<Part, Error>,
    transform: @escaping @Sendable (Part) -> [Part]
) -> AsyncThrowingStream<Part, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await chunk in source {
                    for part in transform(chunk) {
                        continuation.yield(part)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                task.cancel()
            }
        }
    }
}
