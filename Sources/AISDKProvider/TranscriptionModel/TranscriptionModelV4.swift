import Foundation

/**
 Transcription model specification version 4.

 Port of `@ai-sdk/provider/src/transcription-model/v4/transcription-model-v4.ts`.
 */
public protocol TranscriptionModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }

    func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result
}

extension TranscriptionModelV4 {
    public var specificationVersion: String { "v4" }
}

public struct TranscriptionModelV4Result: Sendable {
    public let text: String
    public let segments: [Segment]
    public let language: String?
    public let durationInSeconds: Double?
    public let warnings: [SharedV4Warning]
    public let request: RequestInfo?
    public let response: ResponseInfo
    public let providerMetadata: [String: JSONObject]?

    public init(
        text: String,
        segments: [Segment],
        language: String? = nil,
        durationInSeconds: Double? = nil,
        warnings: [SharedV4Warning] = [],
        request: RequestInfo? = nil,
        response: ResponseInfo,
        providerMetadata: [String: JSONObject]? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }

    public struct Segment: Sendable, Equatable, Codable {
        public let text: String
        public let startSecond: Double
        public let endSecond: Double

        public init(text: String, startSecond: Double, endSecond: Double) {
            self.text = text
            self.startSecond = startSecond
            self.endSecond = endSecond
        }
    }

    public struct RequestInfo: Sendable {
        public let body: String?

        public init(body: String? = nil) {
            self.body = body
        }
    }

    public struct ResponseInfo: @unchecked Sendable {
        public let timestamp: Date
        public let modelId: String
        public let headers: SharedV4Headers?
        public let body: Any?

        public init(
            timestamp: Date,
            modelId: String,
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
