import Foundation

/**
 Speech model specification version 4.

 Port of `@ai-sdk/provider/src/speech-model/v4/speech-model-v4.ts`.
 */
public protocol SpeechModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }

    func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result
}

extension SpeechModelV4 {
    public var specificationVersion: String { "v4" }
}

public struct SpeechModelV4Result: Sendable {
    public let audio: SpeechModelV4Audio
    public let warnings: [SharedV4Warning]
    public let request: RequestInfo?
    public let response: ResponseInfo
    public let providerMetadata: [String: JSONObject]?

    public init(
        audio: SpeechModelV4Audio,
        warnings: [SharedV4Warning] = [],
        request: RequestInfo? = nil,
        response: ResponseInfo,
        providerMetadata: [String: JSONObject]? = nil
    ) {
        self.audio = audio
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }

    public struct RequestInfo: @unchecked Sendable {
        public let body: Any?

        public init(body: Any? = nil) {
            self.body = body
        }
    }

    public struct ResponseInfo: @unchecked Sendable {
        public let timestamp: Date
        public let modelId: String
        public let headers: SharedV2Headers?
        public let body: Any?

        public init(
            timestamp: Date,
            modelId: String,
            headers: SharedV2Headers? = nil,
            body: Any? = nil
        ) {
            self.timestamp = timestamp
            self.modelId = modelId
            self.headers = headers
            self.body = body
        }
    }
}

public enum SpeechModelV4Audio: Sendable, Equatable {
    case base64(String)
    case binary(Data)
}
