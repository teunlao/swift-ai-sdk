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

 The body reaches the fetch function as `URLRequest.httpBodyStream`. When the
 request fails or is abandoned, the body producer is cancelled and stops
 consuming the part streams. Callers with fully buffered payloads can keep using
 `postFormDataToAPI`.

 Port of `@ai-sdk/provider-utils/src/post-multipart-stream-to-api.ts`.
 */
public func postMultipartStreamToAPI<T>(
    url: String,
    headers: [String: String?]? = nil,
    parts: [MultipartStreamPart],
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
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

    var request = try makeAPIRequest(
        url: url,
        method: "POST",
        headers: requestHeaders,
        requestBodyValues: requestBodyValues
    )

    let body = MultipartRequestBodyStream(
        source: makeMultipartBodyStream(parts: parts, boundary: boundary)
    )
    request.httpBodyStream = body.inputStream
    defer { body.dispose() }

    return try await sendAPIRequest(
        request,
        url: url,
        requestBodyValues: requestBodyValues,
        failedResponseHandler: failedResponseHandler,
        successfulResponseHandler: successfulResponseHandler,
        isAborted: isAborted,
        fetch: fetch
    )
}

// Header parameter values must not smuggle CR/LF or break the quoted string.
private func escapeMultipartHeaderValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func makeMultipartBodyStream(
    parts: [MultipartStreamPart],
    boundary: String
) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for part in parts {
                    try Task.checkCancellation()

                    let disposition = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(escapeMultipartHeaderValue(part.name))\""

                    switch part {
                    case let .field(_, value):
                        continuation.yield(Data("\(disposition)\r\n\r\n\(value)\r\n".utf8))

                    case let .file(_, filename, mediaType, content):
                        // A filename is always emitted: without it, multipart parsers
                        // treat the part as a scalar field.
                        let filenameParameter = "; filename=\"\(escapeMultipartHeaderValue(filename ?? "blob"))\""
                        let contentType = (mediaType ?? "application/octet-stream")
                            .replacingOccurrences(of: "\r", with: "")
                            .replacingOccurrences(of: "\n", with: "")
                        continuation.yield(Data("\(disposition)\(filenameParameter)\r\nContent-Type: \(contentType)\r\n\r\n".utf8))

                        switch content {
                        case .data(let data):
                            continuation.yield(data)
                        case .stream(let stream):
                            for try await chunk in stream {
                                try Task.checkCancellation()
                                continuation.yield(chunk)
                            }
                        }

                        continuation.yield(Data("\r\n".utf8))
                    }
                }

                continuation.yield(Data("--\(boundary)--\r\n".utf8))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}

/**
 Bridges an async byte stream to the `InputStream` a `URLRequest` body needs.
 A writer task copies chunks into a bound stream pair; `dispose` cancels it,
 which stops it from consuming the source.
 */
private final class MultipartRequestBodyStream: @unchecked Sendable {
    let inputStream: InputStream
    private let writer: Task<Void, Never>

    init(source: AsyncThrowingStream<Data, Error>, bufferSize: Int = 64 * 1024) {
        var input: InputStream?
        var output: OutputStream?
        Stream.getBoundStreams(withBufferSize: bufferSize, inputStream: &input, outputStream: &output)

        // `getBoundStreams` always provides both streams.
        let inputStream = input!
        let outputStream = output!
        self.inputStream = inputStream

        writer = Task {
            outputStream.open()
            defer { outputStream.close() }

            do {
                for try await chunk in source {
                    guard try await Self.write(chunk, to: outputStream) else {
                        return
                    }
                }
            } catch {
                // The reader sees end-of-stream; the request fails on its side.
            }
        }
    }

    func dispose() {
        writer.cancel()
    }

    /// Returns `false` when the reader closed the pipe or the writer was cancelled.
    private static func write(_ chunk: Data, to stream: OutputStream) async throws -> Bool {
        var offset = 0
        while offset < chunk.count {
            try Task.checkCancellation()

            // Bound streams expose no async readiness signal, so wait briefly for buffer space.
            guard stream.hasSpaceAvailable else {
                try await Task.sleep(nanoseconds: 1_000_000)
                continue
            }

            let written = chunk.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return stream.write(base.advanced(by: offset), maxLength: chunk.count - offset)
            }

            if written <= 0 {
                return false
            }
            offset += written
        }
        return true
    }
}
