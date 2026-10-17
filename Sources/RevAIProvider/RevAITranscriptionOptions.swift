import AISDKProvider

public struct RevAITranscriptionModelOptions: Codable, Sendable, Equatable {
    public enum DiarizationType: String, Codable, Sendable {
        case standard, premium
    }

    public struct NotificationConfig: Codable, Sendable, Equatable {
        public struct AuthHeaders: Codable, Sendable, Equatable {
            public var authorization: String
            public init(authorization: String) { self.authorization = authorization }
            enum CodingKeys: String, CodingKey { case authorization = "Authorization" }
        }

        public var url: String
        public var authHeaders: AuthHeaders?
        public init(url: String, authHeaders: AuthHeaders? = nil) {
            self.url = url
            self.authHeaders = authHeaders
        }
        enum CodingKeys: String, CodingKey { case url; case authHeaders = "auth_headers" }
    }

    public struct Segment: Codable, Sendable, Equatable {
        public var start: Double
        public var end: Double
        public init(start: Double, end: Double) { self.start = start; self.end = end }
    }

    public struct SpeakerName: Codable, Sendable, Equatable {
        public var displayName: String
        public init(displayName: String) { self.displayName = displayName }
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }

    public struct SummarizationConfig: Codable, Sendable, Equatable {
        public enum Model: String, Codable, Sendable { case standard, premium }
        public enum Format: String, Codable, Sendable { case paragraph, bullets }
        public var model: Model?
        public var type: Format?
        public var prompt: String?
        public init(model: Model? = nil, type: Format? = nil, prompt: String? = nil) {
            self.model = model
            self.type = type
            self.prompt = prompt
        }
    }

    public struct TranslationConfig: Codable, Sendable, Equatable {
        public enum Model: String, Codable, Sendable { case standard, premium }
        public struct TargetLanguage: Codable, Sendable, Equatable {
            public enum Language: String, Codable, Sendable {
                case en, ar, pt, fr, es, it, ja, ko, de, ru
                case enUS = "en-us", enGB = "en-gb"
                case ptBR = "pt-br", ptPT = "pt-pt", frCA = "fr-ca"
                case esES = "es-es", esLA = "es-la"
            }
            public var language: Language
            public init(language: Language) { self.language = language }
        }
        public var targetLanguages: [TargetLanguage]
        public var model: Model?
        public init(targetLanguages: [TargetLanguage], model: Model? = nil) {
            self.targetLanguages = targetLanguages
            self.model = model
        }
        enum CodingKeys: String, CodingKey { case targetLanguages = "target_languages"; case model }
    }

    public var metadata: String?
    public var notificationConfig: NotificationConfig?
    public var deleteAfterSeconds: Double?
    public var verbatim: Bool?
    public var rush: Bool?
    public var testMode: Bool?
    public var segmentsToTranscribe: [Segment]?
    public var speakerNames: [SpeakerName]?
    public var skipDiarization: Bool?
    public var skipPostprocessing: Bool?
    public var skipPunctuation: Bool?
    public var removeDisfluencies: Bool?
    public var removeAtmospherics: Bool?
    public var filterProfanity: Bool?
    public var speakerChannelsCount: Double?
    public var speakersCount: Double?
    public var diarizationType: DiarizationType?
    public var customVocabularyId: String?
    public var customVocabularies: [JSONObject]?
    public var strictCustomVocabulary: Bool?
    public var summarizationConfig: SummarizationConfig?
    public var translationConfig: TranslationConfig?
    public var language: String?
    public var forcedAlignment: Bool?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case metadata, verbatim, rush, language
        case notificationConfig = "notification_config"
        case deleteAfterSeconds = "delete_after_seconds"
        case testMode = "test_mode"
        case segmentsToTranscribe = "segments_to_transcribe"
        case speakerNames = "speaker_names"
        case skipDiarization = "skip_diarization"
        case skipPostprocessing = "skip_postprocessing"
        case skipPunctuation = "skip_punctuation"
        case removeDisfluencies = "remove_disfluencies"
        case removeAtmospherics = "remove_atmospherics"
        case filterProfanity = "filter_profanity"
        case speakerChannelsCount = "speaker_channels_count"
        case speakersCount = "speakers_count"
        case diarizationType = "diarization_type"
        case customVocabularyId = "custom_vocabulary_id"
        case customVocabularies = "custom_vocabularies"
        case strictCustomVocabulary = "strict_custom_vocabulary"
        case summarizationConfig = "summarization_config"
        case translationConfig = "translation_config"
        case forcedAlignment = "forced_alignment"
    }
}
