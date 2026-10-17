public protocol LanguageModelConvertible: Sendable {
    var languageModel: LanguageModel { get }
}

public enum LanguageModel: LanguageModelConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case id(String)
    case model(any LanguageModelV4)
    public var languageModel: LanguageModel { self }
    public init(stringLiteral value: String) { self = .id(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self = .id(String(stringInterpolation: stringInterpolation)) }
}

extension LanguageModelV4 {
    public var languageModel: LanguageModel { .model(self) }
}

public protocol EmbeddingModelConvertible: Sendable {
    var embeddingModel: EmbeddingModel { get }
}

public enum EmbeddingModel: EmbeddingModelConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case id(String)
    case model(any EmbeddingModelV4)
    public var embeddingModel: EmbeddingModel { self }
    public init(stringLiteral value: String) { self = .id(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self = .id(String(stringInterpolation: stringInterpolation)) }
}

extension EmbeddingModelV4 {
    public var embeddingModel: EmbeddingModel { .model(self) }
}

public protocol ImageModelConvertible: Sendable {
    var imageModel: ImageModel { get }
}

public enum ImageModel: ImageModelConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case id(String)
    case model(any ImageModelV4)
    public var imageModel: ImageModel { self }
    public init(stringLiteral value: String) { self = .id(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self = .id(String(stringInterpolation: stringInterpolation)) }
}

extension ImageModelV4 {
    public var imageModel: ImageModel { .model(self) }
}

public protocol SpeechModelConvertible: Sendable {
    var speechModel: SpeechModel { get }
}

public enum SpeechModel: SpeechModelConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case id(String)
    case model(any SpeechModelV4)
    public var speechModel: SpeechModel { self }
    public init(stringLiteral value: String) { self = .id(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self = .id(String(stringInterpolation: stringInterpolation)) }
}

extension SpeechModelV4 {
    public var speechModel: SpeechModel { .model(self) }
}

public protocol TranscriptionModelConvertible: Sendable {
    var transcriptionModel: TranscriptionModel { get }
}

public enum TranscriptionModel: TranscriptionModelConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case id(String)
    case model(any TranscriptionModelV4)
    public var transcriptionModel: TranscriptionModel { self }
    public init(stringLiteral value: String) { self = .id(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self = .id(String(stringInterpolation: stringInterpolation)) }
}

extension TranscriptionModelV4 {
    public var transcriptionModel: TranscriptionModel { .model(self) }
}

public protocol VideoModelConvertible: Sendable {
    var videoModel: VideoModel { get }
}

public enum VideoModel: VideoModelConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case id(String)
    case model(any VideoModelV4)
    public var videoModel: VideoModel { self }
    public init(stringLiteral value: String) { self = .id(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self = .id(String(stringInterpolation: stringInterpolation)) }
}

extension VideoModelV4 {
    public var videoModel: VideoModel { .model(self) }
}

public protocol RerankingModelConvertible: Sendable {
    var rerankingModel: RerankingModel { get }
}

public enum RerankingModel: RerankingModelConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case id(String)
    case model(any RerankingModelV4)
    public var rerankingModel: RerankingModel { self }
    public init(stringLiteral value: String) { self = .id(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self = .id(String(stringInterpolation: stringInterpolation)) }
}

extension RerankingModelV4 {
    public var rerankingModel: RerankingModel { .model(self) }
}

extension String: LanguageModelConvertible, EmbeddingModelConvertible, ImageModelConvertible, SpeechModelConvertible,
    TranscriptionModelConvertible, VideoModelConvertible, RerankingModelConvertible {
    public var languageModel: LanguageModel { .id(self) }
    public var embeddingModel: EmbeddingModel { .id(self) }
    public var imageModel: ImageModel { .id(self) }
    public var speechModel: SpeechModel { .id(self) }
    public var transcriptionModel: TranscriptionModel { .id(self) }
    public var videoModel: VideoModel { .id(self) }
    public var rerankingModel: RerankingModel { .id(self) }
}
