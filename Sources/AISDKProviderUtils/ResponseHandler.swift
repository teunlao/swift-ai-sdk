import Foundation
import AISDKProvider

/**
 Creates response handlers that mirror
 `@ai-sdk/provider-utils/src/response-handler.ts`.

 These helpers process HTTP responses (JSON, NDJSON streams, binary payloads,
 error payloads) and wrap them into strongly typed results or `APICallError`s.
 */

public struct ResponseHandlerInput: Sendable {
    public let url: String
    private let requestBodyValuesStorage: AnySendable?
    public let response: ProviderHTTPResponse

    public init(url: String, requestBodyValues: Any?, response: ProviderHTTPResponse) {
        self.url = url
        if let requestBodyValues {
            self.requestBodyValuesStorage = AnySendable(requestBodyValues)
        } else {
            self.requestBodyValuesStorage = nil
        }
        self.response = response
    }

    public var requestBodyValues: Any? {
        requestBodyValuesStorage?.value
    }
}

public struct ResponseHandlerResult<Value>: @unchecked Sendable {
    public let value: Value
    public let rawValue: Any?
    public let responseHeaders: [String: String]

    public init(value: Value, rawValue: Any? = nil, responseHeaders: [String: String]) {
        self.value = value
        self.rawValue = rawValue
        self.responseHeaders = responseHeaders
    }
}

public typealias ResponseHandler<Value> = @Sendable (ResponseHandlerInput) async throws -> ResponseHandlerResult<Value>

/**
 Passes a successful response body through while turning a failed read into an
 `APICallError` ("Failed to process successful response"), retryable when a
 network failure caused it. Abort errors pass through unchanged.
 */
private func wrapResponseBodyStream(_ input: ResponseHandlerInput) -> AsyncThrowingStream<Data, Error> {
    // Pull-based like upstream (one source read per consumer pull).
    let source = AsyncIteratorBox(input.response.body.makeStream().makeAsyncIterator())

    return AsyncThrowingStream {
        do {
            return try await source.next()
        } catch {
            if isAbortError(error) {
                throw error
            }

            throw handleFetchError(
                error: APICallError(
                    message: "Failed to process successful response",
                    url: input.url,
                    requestBodyValues: input.requestBodyValues,
                    statusCode: input.response.statusCode,
                    responseHeaders: extractResponseHeaders(from: input.response.httpResponse),
                    cause: error
                ),
                url: input.url,
                requestBodyValues: input.requestBodyValues
            )
        }
    }
}

private func readResponseBodyAsText(_ input: ResponseHandlerInput) async throws -> String {
    try await readResponseWithSizeLimit(response: input.response, url: input.url).utf8String()
}

// MARK: - JSON Error Response Handler

public func createJsonErrorResponseHandler<T>(
    errorSchema: FlexibleSchema<T>,
    errorToMessage: @escaping @Sendable (T) -> String,
    isRetryable: (@Sendable (ProviderHTTPResponse, T?) -> Bool)? = nil
) -> ResponseHandler<APICallError> {
    { input in
        let response = input.response
        let bodyText = try await readResponseBodyAsText(input)
        let headers = extractResponseHeaders(from: response.httpResponse)
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return ResponseHandlerResult(
                value: APICallError(
                    message: response.statusText,
                    url: input.url,
                    requestBodyValues: input.requestBodyValues,
                    statusCode: response.statusCode,
                    responseHeaders: headers,
                    responseBody: bodyText,
                    isRetryable: isRetryable?(response, nil)
                ),
                responseHeaders: headers
            )
        }

        do {
            let parsed = try await parseJSON(
                ParseJSONWithSchemaOptions(text: bodyText, schema: errorSchema)
            )

            return ResponseHandlerResult(
                value: APICallError(
                    message: errorToMessage(parsed),
                    url: input.url,
                    requestBodyValues: input.requestBodyValues,
                    statusCode: response.statusCode,
                    responseHeaders: headers,
                    responseBody: bodyText,
                    isRetryable: isRetryable?(response, parsed),
                    data: parsed
                ),
                rawValue: parsed,
                responseHeaders: headers
            )
        } catch {
            return ResponseHandlerResult(
                value: APICallError(
                    message: response.statusText,
                    url: input.url,
                    requestBodyValues: input.requestBodyValues,
                    statusCode: response.statusCode,
                    responseHeaders: headers,
                    responseBody: bodyText,
                    isRetryable: isRetryable?(response, nil)
                ),
                responseHeaders: headers
            )
        }
    }
}

// MARK: - Event Source Response Handler

public func createEventSourceResponseHandler<T>(
    chunkSchema: FlexibleSchema<T>
) -> ResponseHandler<AsyncThrowingStream<ParseJSONResult<T>, Error>> {
    { input in
        let response = input.response
        if case .none = response.body {
            throw EmptyResponseBodyError()
        }

        let headers = extractResponseHeaders(from: response.httpResponse)

        return ResponseHandlerResult(
            value: parseJsonEventStream(
                stream: wrapResponseBodyStream(input),
                schema: chunkSchema
            ),
            responseHeaders: headers
        )
    }
}

// MARK: - JSON Stream Response Handler

public func createJsonStreamResponseHandler<T>(
    chunkSchema: FlexibleSchema<T>
) -> ResponseHandler<AsyncThrowingStream<ParseJSONResult<T>, Error>> {
    { input in
        let response = input.response
        if case .none = response.body {
            throw EmptyResponseBodyError()
        }

        let headers = extractResponseHeaders(from: response.httpResponse)
        let lines = JSONLineReader(source: AsyncIteratorBox(wrapResponseBodyStream(input).makeAsyncIterator()))
        let schema = chunkSchema

        let outputStream = AsyncThrowingStream<ParseJSONResult<T>, Error> {
            guard let line = try await lines.nextLine() else {
                return nil
            }
            return await safeParseJSON(ParseJSONWithSchemaOptions(text: line, schema: schema))
        }

        return ResponseHandlerResult(
            value: outputStream,
            responseHeaders: headers
        )
    }
}

// MARK: - JSON Response Handler

public func createJsonResponseHandler<T>(
    responseSchema: FlexibleSchema<T>
) -> ResponseHandler<T> {
    { input in
        let response = input.response
        let bodyText = try await readResponseBodyAsText(input)
        let headers = extractResponseHeaders(from: response.httpResponse)

        let parsed = await safeParseJSON(
            ParseJSONWithSchemaOptions(text: bodyText, schema: responseSchema)
        )

        switch parsed {
        case .success(let value, let raw):
            return ResponseHandlerResult(
                value: value,
                rawValue: raw,
                responseHeaders: headers
            )
        case .failure(let error, _):
            throw APICallError(
                message: "Invalid JSON response",
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode,
                responseHeaders: headers,
                responseBody: bodyText,
                cause: error
            )
        }
    }
}

// MARK: - Binary Response Handler

public func createBinaryResponseHandler() -> ResponseHandler<Data> {
    { input in
        let response = input.response
        if case .none = response.body {
            throw APICallError(
                message: "Response body is empty",
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode,
                responseHeaders: extractResponseHeaders(from: response.httpResponse),
                responseBody: nil
            )
        }

        let headers = extractResponseHeaders(from: response.httpResponse)

        do {
            let data = try await response.body.collectData()
            return ResponseHandlerResult(
                value: data,
                responseHeaders: headers
            )
        } catch {
            throw APICallError(
                message: "Failed to read response as array buffer",
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode,
                responseHeaders: headers,
                responseBody: nil,
                cause: error
            )
        }
    }
}

// MARK: - Binary Stream Response Handler

/**
 Passes the response body through as a byte stream without buffering it
 (unlike `createBinaryResponseHandler`). The consumer drains or drops the stream.
 */
public func createBinaryStreamResponseHandler() -> ResponseHandler<AsyncThrowingStream<Data, Error>> {
    { input in
        if case .none = input.response.body {
            throw EmptyResponseBodyError()
        }

        return ResponseHandlerResult(
            value: wrapResponseBodyStream(input),
            responseHeaders: extractResponseHeaders(from: input.response.httpResponse)
        )
    }
}

// MARK: - Status Code Error Handler

public func createStatusCodeErrorResponseHandler() -> ResponseHandler<APICallError> {
    { input in
        let response = input.response
        let headers = extractResponseHeaders(from: response.httpResponse)
        let bodyText = try await readResponseBodyAsText(input)

        return ResponseHandlerResult(
            value: APICallError(
                message: response.statusText,
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode,
                responseHeaders: headers,
                responseBody: bodyText
            ),
            responseHeaders: headers
        )
    }
}

// MARK: - Helpers

/// Splits a byte stream into newline-delimited lines, pulling a chunk only when no
/// complete line is buffered. Bytes are decoded per line, so multi-byte UTF-8
/// sequences split across chunks stay intact.
private final class JSONLineReader: @unchecked Sendable {
    private let source: AsyncIteratorBox<AsyncThrowingStream<Data, Error>.AsyncIterator>
    private var buffer = Data()
    private var isFinished = false

    init(source: AsyncIteratorBox<AsyncThrowingStream<Data, Error>.AsyncIterator>) {
        self.source = source
    }

    func nextLine() async throws -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }

            if isFinished {
                guard !buffer.isEmpty else {
                    return nil
                }
                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll()
                return line
            }

            if let chunk = try await source.next() {
                buffer.append(chunk)
            } else {
                isFinished = true
            }
        }
    }
}

private extension Data {
    func utf8String() -> String {
        String(data: self, encoding: .utf8) ?? ""
    }
}
