import Foundation

func writeToServerResponse(
    response: any StreamTextResponseWriter,
    stream: AsyncThrowingStream<String, Error>
) async throws {
    let source = createAsyncIterableStream(source: stream)
    let writer = Task {
        do {
            for try await chunk in source {
                try Task.checkCancellation()
                if response.isClosed { break }
                try await response.write(Data(chunk.utf8))
            }
        } catch {
            await source.cancel()
            throw error
        }
    }
    let removeListener = response.onClose {
        writer.cancel()
        Task { await source.cancel() }
    }
    if response.isClosed {
        writer.cancel()
        await source.cancel()
    }
    defer {
        removeListener()
        if !response.isClosed { response.end() }
    }
    try await withTaskCancellationHandler {
        do { try await writer.value }
        catch {
            if !response.isClosed { throw error }
        }
    } onCancel: {
        writer.cancel()
        Task { await source.cancel() }
    }
}
