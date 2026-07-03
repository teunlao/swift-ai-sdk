import Foundation

/**
 Result of a streaming transcription call.

 Port of `@ai-sdk/provider/src/transcription-model/v4/transcription-model-v4-stream-result.ts`.
 */
public struct TranscriptionModelV4StreamResult: Sendable {
    public let stream: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>
    public let request: RequestInfo?
    public let response: ResponseInfo?

    public init(
        stream: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>,
        request: RequestInfo? = nil,
        response: ResponseInfo? = nil
    ) {
        self.stream = stream
        self.request = request
        self.response = response
    }

    public struct RequestInfo: @unchecked Sendable {
        public let body: Any?

        public init(body: Any? = nil) {
            self.body = body
        }
    }

    public struct ResponseInfo: @unchecked Sendable {
        public let timestamp: Date?
        public let modelId: String?
        public let headers: SharedV4Headers?
        public let body: Any?

        public init(
            timestamp: Date? = nil,
            modelId: String? = nil,
            headers: SharedV4Headers? = nil,
            body: Any? = nil
        ) {
            self.timestamp = timestamp
            self.modelId = modelId
            self.headers = headers
            self.body = body
        }
    }
}
