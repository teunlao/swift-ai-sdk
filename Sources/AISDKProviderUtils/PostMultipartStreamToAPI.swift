import Foundation
import AISDKProvider

/**
 A part of a streaming `multipart/form-data` request body.

 Parts are emitted in array order, which providers may depend on (e.g. xAI
 requires expiry fields to precede the file part).

 Port of `MultipartStreamPart` from `@ai-sdk/provider-utils/src/post-multipart-stream-to-api.ts`.
 */
public enum MultipartStreamPart: Sendable {
    case field(name: String, value: String)
    case file(name: String, filename: String? = nil, mediaType: String? = nil, content: MultipartStreamFileContent)

    var name: String {
        switch self {
        case .field(let name, _), .file(let name, _, _, _):
            return name
        }
    }
}

/// File content of a streaming multipart part.
public enum MultipartStreamFileContent: Sendable {
    case data(Data)
    case stream(AsyncThrowingStream<Data, Error>)
}

/**
 POSTs a `multipart/form-data` body as a request stream, so file parts backed by
 a stream are sent without buffering the whole file in memory.

 The body reaches the fetch function as `URLRequest.httpBodyStream` and is
 produced on demand: a source chunk is read only after the previous one was
 handed to the reader. A failing source fails the request with its error, even
 when the server already answered. When the request ends, the body is released
 before this function returns: the producer stops, and every part stream that
 was not read to its end is cancelled. Callers with fully buffered payloads can
 keep using `postFormDataToAPI`.

 Port of `@ai-sdk/provider-utils/src/post-multipart-stream-to-api.ts`.
 */
public func postMultipartStreamToAPI<T>(
    url: String,
    headers: [String: String?]? = nil,
    parts: [MultipartStreamPart],
    failedResponseHandler: @escaping ResponseHandler<APICallError>,
    successfulResponseHandler: @escaping ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> ResponseHandlerResult<T> {
    let boundary = "ai-sdk-multipart-\(generateID())"

    // Stream contents cannot be replayed for error reporting; expose part names,
    // field values and file placeholders only.
    var requestBodyValues: [String: String] = [:]
    for part in parts {
        switch part {
        case let .field(name, value):
            requestBodyValues[name] = value
        case let .file(name, filename, _, _):
            requestBodyValues[name] = "<file:\(filename ?? name)>"
        }
    }

    var requestHeaders = headers ?? [:]
    requestHeaders["Content-Type"] = "multipart/form-data; boundary=\(boundary)"

    let source = MultipartBodySource(parts: parts, boundary: boundary)
    var request: URLRequest
    do {
        request = try makeAPIRequest(
            url: url,
            method: "POST",
            headers: requestHeaders,
            requestBodyValues: requestBodyValues
        )
    } catch {
        await source.cancelUnfinishedStreams()
        throw error
    }

    let body = StreamingRequestBody(source: source)
    request.httpBodyStream = body.inputStream

    let requestTask = Task { [request, requestBodyValues] in
        try await sendAPIRequest(
            request,
            url: url,
            requestBodyValues: requestBodyValues,
            failedResponseHandler: failedResponseHandler,
            successfulResponseHandler: successfulResponseHandler,
            isAborted: isAborted,
            fetch: fetch
        )
    }
    // A failing source cancels the in-flight request.
    body.start(onSourceError: { requestTask.cancel() })

    let result = await withTaskCancellationHandler {
        await requestTask.result
    } onCancel: {
        requestTask.cancel()
    }

    // Release every source deterministically: fetch implementations do not
    // reliably cancel streaming request bodies on rejection or abort.
    let sourceError = await body.dispose()

    if let sourceError {
        throw handleFetchError(error: sourceError, url: url, requestBodyValues: requestBodyValues)
    }
    return try result.get()
}

// Header parameter values must not smuggle CR/LF or break the quoted string.
private func escapeMultipartHeaderValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

/**
 Produces the multipart body one chunk per `next()`. Only the body pump calls
 `next()`; `cancelUnfinishedStreams` runs after the pump stopped.
 */
private final class MultipartBodySource: @unchecked Sendable {
    private enum State {
        case partStart(Int)
        case streamContent(Int, AsyncIteratorBox<AsyncThrowingStream<Data, Error>.AsyncIterator>)
        case partEnd(Int)
        case closingBoundary
        case done
    }

    private let parts: [MultipartStreamPart]
    private let boundary: String
    private var state: State = .partStart(0)
    private var finishedStreams: Set<Int> = []

    init(parts: [MultipartStreamPart], boundary: String) {
        self.parts = parts
        self.boundary = boundary
    }

    func next() async throws -> Data? {
        while true {
            try Task.checkCancellation()

            switch state {
            case .partStart(let index):
                guard index < parts.count else {
                    state = .closingBoundary
                    continue
                }

                let part = parts[index]
                let disposition = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(escapeMultipartHeaderValue(part.name))\""

                switch part {
                case let .field(_, value):
                    state = .partStart(index + 1)
                    return Data("\(disposition)\r\n\r\n\(value)\r\n".utf8)

                case let .file(_, filename, mediaType, content):
                    // A filename is always emitted: without it, multipart parsers
                    // treat the part as a scalar field.
                    let filenameParameter = "; filename=\"\(escapeMultipartHeaderValue(filename ?? "blob"))\""
                    let contentType = (mediaType ?? "application/octet-stream")
                        .replacingOccurrences(of: "\r", with: "")
                        .replacingOccurrences(of: "\n", with: "")
                    var header = Data("\(disposition)\(filenameParameter)\r\nContent-Type: \(contentType)\r\n\r\n".utf8)

                    switch content {
                    case .data(let data):
                        header.append(data)
                        state = .partEnd(index)
                    case .stream(let stream):
                        state = .streamContent(index, AsyncIteratorBox(stream.makeAsyncIterator()))
                    }
                    return header
                }

            case let .streamContent(index, source):
                if let chunk = try await source.next() {
                    // A cancelled pump must not report a source truncated by its own cancellation as finished.
                    try Task.checkCancellation()
                    return chunk
                }
                try Task.checkCancellation()
                finishedStreams.insert(index)
                state = .partEnd(index)

            case .partEnd(let index):
                state = .partStart(index + 1)
                return Data("\r\n".utf8)

            case .closingBoundary:
                state = .done
                return Data("--\(boundary)--\r\n".utf8)

            case .done:
                return nil
            }
        }
    }

    /// Cancels the active part stream and every part stream not yet read.
    func cancelUnfinishedStreams() async {
        for (index, part) in parts.enumerated() {
            if case .file(_, _, _, .stream(let stream)) = part, !finishedStreams.contains(index) {
                await cancelStream(stream)
            }
        }
    }
}

/**
 Bridges the multipart source to the `InputStream` a `URLRequest` body needs.

 A pump task pulls one chunk at a time and hands it to a writer thread, which
 blocks on the bound stream pair until the reader takes the bytes; the next
 chunk is pulled only after that. Disposal stops the pump, unblocks and joins
 the writer, and cancels unfinished part streams.
 */
private final class StreamingRequestBody: @unchecked Sendable {
    let inputStream: InputStream

    private let source: MultipartBodySource
    private let outputStream: OutputStream
    private let condition = NSCondition()
    private var pendingChunk: Data?
    private var chunkHandled: CheckedContinuation<Bool, Never>?
    private var isClosing = false
    private var writerStopped = false
    private var writerExited = false
    private var writerExit: CheckedContinuation<Void, Never>?
    private var sourceError: Error?
    private var pump: Task<Void, Never>?

    init(source: MultipartBodySource, bufferSize: Int = 64 * 1024) {
        self.source = source

        var input: InputStream?
        var output: OutputStream?
        Stream.getBoundStreams(withBufferSize: bufferSize, inputStream: &input, outputStream: &output)
        // `getBoundStreams` always provides both streams.
        inputStream = input!
        outputStream = output!
    }

    func start(onSourceError: @escaping @Sendable () -> Void) {
        let writer = Thread { [self] in runWriter() }
        writer.name = "ai-sdk.multipart-body-writer"
        writer.start()

        pump = Task { [self] in
            do {
                while let chunk = try await source.next() {
                    guard await hand(chunk) else {
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    recordSourceError(error)
                    onSourceError()
                }
            }
            closeWriter()
        }
    }

    /// Stops producing, releases every source, and returns the source failure, if any.
    func dispose() async -> Error? {
        pump?.cancel()
        closeWriter()
        // Closing the read end fails a write blocked on a reader that stopped reading.
        inputStream.close()
        await pump?.value

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            condition.lock()
            if writerExited {
                condition.unlock()
                continuation.resume()
                return
            }
            writerExit = continuation
            condition.unlock()
        }

        await source.cancelUnfinishedStreams()
        return recordedSourceError()
    }

    private func recordSourceError(_ error: Error) {
        condition.lock()
        sourceError = error
        condition.unlock()
    }

    private func recordedSourceError() -> Error? {
        condition.lock()
        defer { condition.unlock() }
        return sourceError
    }

    /// Hands a chunk to the writer and waits until it is written; `false` once the reader is gone.
    private func hand(_ chunk: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            condition.lock()
            guard !writerStopped, !isClosing else {
                condition.unlock()
                continuation.resume(returning: false)
                return
            }
            pendingChunk = chunk
            chunkHandled = continuation
            condition.signal()
            condition.unlock()
        }
    }

    private func closeWriter() {
        condition.lock()
        isClosing = true
        condition.signal()
        condition.unlock()
    }

    private func runWriter() {
        outputStream.open()

        while true {
            condition.lock()
            while pendingChunk == nil && !isClosing {
                condition.wait()
            }
            guard let chunk = pendingChunk else {
                condition.unlock()
                break
            }
            condition.unlock()

            let written = write(chunk)

            condition.lock()
            pendingChunk = nil
            if !written {
                writerStopped = true
            }
            let handled = chunkHandled
            chunkHandled = nil
            condition.unlock()
            handled?.resume(returning: written)

            if !written {
                break
            }
        }

        outputStream.close()

        condition.lock()
        writerExited = true
        // A chunk handed after the writer stopped is never written.
        let handled = chunkHandled
        chunkHandled = nil
        let exit = writerExit
        writerExit = nil
        condition.unlock()
        handled?.resume(returning: false)
        exit?.resume()
    }

    /// Blocks until the reader takes every byte; `false` when the pair was closed.
    private func write(_ chunk: Data) -> Bool {
        chunk.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return true
            }
            var offset = 0
            while offset < buffer.count {
                let written = outputStream.write(base.advanced(by: offset), maxLength: buffer.count - offset)
                if written <= 0 {
                    return false
                }
                offset += written
            }
            return true
        }
    }
}
