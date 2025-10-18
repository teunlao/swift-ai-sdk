import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streaming result returned by `streamText`.

 Port of `@ai-sdk/ai/src/generate-text/stream-text-result.ts`.

 The result exposes async accessors that consume the underlying stream on-demand,
 along with helper streams for text deltas and complete event sequences.
 */
public protocol StreamTextResult: Sendable {
    /// Structured partial output type emitted during streaming.
    associatedtype Output: Sendable
    associatedtype PartialOutput: Sendable

    /// Generated content from the final step (consumes the stream).
    var content: [ContentPart] { get async throws }

    /// Generated text from the final step (consumes the stream).
    var text: String { get async throws }

    /// Generated reasoning parts (consumes the stream).
    var reasoning: [ReasoningOutput] { get async throws }

    /// Generated reasoning text (consumes the stream).
    var reasoningText: String? { get async throws }

    /// Generated files (consumes the stream).
    var files: [GeneratedFile] { get async throws }

    /// Generated sources (consumes the stream).
    var sources: [Source] { get async throws }

    /// Tool calls executed in the final step (consumes the stream).
    var toolCalls: [TypedToolCall] { get async throws }

    /// Static tool calls executed in the final step (consumes the stream).
    var staticToolCalls: [StaticToolCall] { get async throws }

    /// Dynamic tool calls executed in the final step (consumes the stream).
    var dynamicToolCalls: [DynamicToolCall] { get async throws }

    /// Tool results produced in the final step (consumes the stream).
    var toolResults: [TypedToolResult] { get async throws }

    /// Static tool results produced in the final step (consumes the stream).
    var staticToolResults: [StaticToolResult] { get async throws }

    /// Dynamic tool results produced in the final step (consumes the stream).
    var dynamicToolResults: [DynamicToolResult] { get async throws }

    /// Finish reason reported by the final step (consumes the stream).
    var finishReason: FinishReason { get async throws }

    /// Token usage of the final step (consumes the stream).
    var usage: LanguageModelUsage { get async throws }

    /// Aggregated token usage across all steps (consumes the stream).
    var totalUsage: LanguageModelUsage { get async throws }

    /// Provider warnings from the first step (consumes the stream).
    var warnings: [CallWarning]? { get async throws }

    /// All step results gathered so far (consumes the stream).
    var steps: [StepResult] { get async throws }

    /// Request metadata of the final step (consumes the stream).
    var request: LanguageModelRequestMetadata { get async throws }

    /// Response metadata of the final step (consumes the stream).
    var response: StepResultResponse { get async throws }

    /// Provider-specific metadata from the final step (consumes the stream).
    var providerMetadata: ProviderMetadata? { get async throws }

    /// Stream of text deltas emitted by the model.
    var textStream: AsyncThrowingStream<String, Error> { get }

    /// Stream of all events (text, reasoning, tool calls/results, etc.).
    var fullStream: AsyncThrowingStream<TextStreamPart, Error> { get }

    /// Stream of partial structured outputs.
    var experimentalPartialOutputStream: AsyncThrowingStream<PartialOutput, Error> { get }

    /// Parsed structured output when `experimentalOutput` is configured.
    var experimentalOutput: Output { get async throws }

    /**
     Consume the underlying stream without processing individual parts.

     - Parameter options: Optional callbacks invoked during consumption.
     */
    func consumeStream(options: ConsumeStreamOptions?) async

    /**
     Convert the stream to a UI message stream (async sequence of message chunks).

     - Parameter options: Stream customisation options.
     - Returns: Async stream of UI message chunks.
     */
    func toUIMessageStream<Message: UIMessageConvertible>(
        options: UIMessageStreamOptions<Message>?
    ) -> AsyncThrowingStream<UIMessageStreamChunk<Message>, Error>

    /**
     Pipe the UI message stream to a response writer (e.g. HTTP response).

     - Parameters:
       - response: Target response writer.
       - options: Response and stream configuration.
     */
    func pipeUIMessageStreamToResponse<Message: UIMessageConvertible>(
        _ response: any StreamTextResponseWriter,
        options: StreamTextUIResponseOptions<Message>?
    )

    /**
     Pipe the text stream to a response writer (e.g. HTTP response).

     - Parameters:
       - response: Target response writer.
       - initOptions: Response configuration (headers, status).
     */
    func pipeTextStreamToResponse(
        _ response: any StreamTextResponseWriter,
        init initOptions: TextStreamResponseInit?
    )

    /**
     Convert the stream to a UI message response object.

     - Parameter options: Response and stream configuration.
     - Returns: Response object containing chunk stream and metadata.
     */
    func toUIMessageStreamResponse<Message: UIMessageConvertible>(
        options: StreamTextUIResponseOptions<Message>?
    ) -> UIMessageStreamResponse<Message>

    /**
     Convert the stream to a plain text response object.

     - Parameter initOptions: Response configuration (headers, status).
     - Returns: Response object containing text chunks.
     */
    func toTextStreamResponse(
        init initOptions: TextStreamResponseInit?
    ) -> TextStreamResponse

    /// Convert the stream into a Server-Sent Events stream.
    func toSSEStream(includeUsage: Bool) -> AsyncThrowingStream<String, Error>
}

/**
Options for consuming a stream result.
 */
public struct ConsumeStreamOptions: Sendable {
    /// Optional error handler invoked when stream consumption fails.
    public let onError: (@Sendable (Error) -> Void)?

    public init(onError: (@Sendable (Error) -> Void)? = nil) {
        self.onError = onError
    }
}

// MARK: - UI Stream Placeholders

/// Chunk emitted by a UI message stream.
public typealias UIMessageStreamChunk<Message: UIMessageConvertible> = InferUIMessageChunk<Message>

/// Options for constructing a UI message stream.
public struct UIMessageStreamOptions<Message: UIMessageConvertible>: Sendable {
    public var originalMessages: [Message]?
    public var generateMessageId: (@Sendable () -> String)?
    public var onFinish: UIMessageStreamOnFinishCallback<Message>?
    public var messageMetadata: (@Sendable (TextStreamPart) -> JSONValue?)?
    public var sendReasoning: Bool
    public var sendSources: Bool
    public var sendFinish: Bool
    public var sendStart: Bool
    public var onError: (@Sendable (Error) -> String)?

    public init(
        originalMessages: [Message]? = nil,
        generateMessageId: (@Sendable () -> String)? = nil,
        onFinish: UIMessageStreamOnFinishCallback<Message>? = nil,
        messageMetadata: (@Sendable (TextStreamPart) -> JSONValue?)? = nil,
        sendReasoning: Bool = false,
        sendSources: Bool = false,
        sendFinish: Bool = true,
        sendStart: Bool = true,
        onError: (@Sendable (Error) -> String)? = nil
    ) {
        self.originalMessages = originalMessages
        self.generateMessageId = generateMessageId
        self.onFinish = onFinish
        self.messageMetadata = messageMetadata
        self.sendReasoning = sendReasoning
        self.sendSources = sendSources
        self.sendFinish = sendFinish
        self.sendStart = sendStart
        self.onError = onError
    }
}

/// Callback invoked when an SSE stream copy should be consumed.
public typealias UIMessageStreamConsumer = @Sendable (AsyncThrowingStream<String, Error>) async throws -> Void

/// Initialisation parameters for UI message responses.
public struct UIMessageStreamResponseInit: Sendable {
    public var headers: [String: String]?
    public var status: Int?
    public var statusText: String?
    public var consumeSSEStream: UIMessageStreamConsumer?

    public init(
        headers: [String: String]? = nil,
        status: Int? = nil,
        statusText: String? = nil,
        consumeSSEStream: UIMessageStreamConsumer? = nil
    ) {
        self.headers = headers
        self.status = status
        self.statusText = statusText
        self.consumeSSEStream = consumeSSEStream
    }
}

/// Combined options for creating UI message stream responses.
public struct StreamTextUIResponseOptions<Message: UIMessageConvertible>: Sendable {
    public var responseInit: UIMessageStreamResponseInit?
    public var streamOptions: UIMessageStreamOptions<Message>?

    public init(
        responseInit: UIMessageStreamResponseInit? = nil,
        streamOptions: UIMessageStreamOptions<Message>? = nil
    ) {
        self.responseInit = responseInit
        self.streamOptions = streamOptions
    }
}

/// Abstraction over a streaming HTTP response writer (e.g. server response).
///
/// Port of the `ServerResponse` usage in `@ai-sdk/ai`.
///
/// Conforming types must be thread-safe because they can be invoked from
/// background tasks while streaming chunks.
public protocol StreamTextResponseWriter: AnyObject, Sendable {
    /// Writes the HTTP status line and headers before streaming begins.
    func writeHead(
        status: Int,
        statusText: String?,
        headers: [String: String]
    )

    /// Writes a single UTF-8 encoded chunk to the underlying response.
    func write(_ data: Data)

    /// Finishes the response after all chunks have been written.
    func end()
}

/// UI message stream response placeholder.
public struct UIMessageStreamResponse<Message: UIMessageConvertible>: Sendable {
    public let stream: AsyncThrowingStream<String, Error>
    public let options: StreamTextUIResponseOptions<Message>?

    public init(
        stream: AsyncThrowingStream<String, Error>,
        options: StreamTextUIResponseOptions<Message>? = nil
    ) {
        self.stream = stream
        self.options = options
    }
}

/// Initialisation parameters for text stream responses.
public struct TextStreamResponseInit: Sendable {
    public var headers: [String: String]?
    public var status: Int?
    public var statusText: String?

    public init(
        headers: [String: String]? = nil,
        status: Int? = nil,
        statusText: String? = nil
    ) {
        self.headers = headers
        self.status = status
        self.statusText = statusText
    }
}

/// Plain text stream response placeholder.
public struct TextStreamResponse: Sendable {
    public let stream: AsyncThrowingStream<String, Error>
    public let initOptions: TextStreamResponseInit?

    public init(
        stream: AsyncThrowingStream<String, Error>,
        initOptions: TextStreamResponseInit? = nil
    ) {
        self.stream = stream
        self.initOptions = initOptions
    }
}
