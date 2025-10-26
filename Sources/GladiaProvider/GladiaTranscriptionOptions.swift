import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gladia/src/gladia-transcription-model.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GladiaTranscriptionOptions: Sendable, Equatable, Codable {
    public enum CustomVocabulary: Sendable, Equatable, Codable {
        case bool(Bool)
        case entries([CustomVocabularyEntry])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .bool(flag)
                return
            }
            if let entries = try? container.decode([CustomVocabularyEntry].self) {
                self = .entries(entries)
                return
            }
            throw DecodingError.typeMismatch(
                CustomVocabulary.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected boolean or array for customVocabulary")
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let flag):
                try container.encode(flag)
            case .entries(let entries):
                try container.encode(entries)
            }
        }
    }

    public enum CustomVocabularyEntry: Sendable, Equatable, Codable {
        case string(String)
        case details(VocabularyTerm)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            if let details = try? container.decode(VocabularyTerm.self) {
                self = .details(details)
                return
            }
            throw DecodingError.typeMismatch(
                CustomVocabularyEntry.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected string or object for custom vocabulary entry")
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .details(let term):
                try container.encode(term)
            }
        }
    }

    public struct VocabularyTerm: Sendable, Equatable, Codable {
        public let value: String
        public let intensity: Double?
        public let pronunciations: [String]?
        public let language: String?

        public init(value: String, intensity: Double? = nil, pronunciations: [String]? = nil, language: String? = nil) {
            self.value = value
            self.intensity = intensity
            self.pronunciations = pronunciations
            self.language = language
        }
    }

    public struct CustomVocabularyConfig: Sendable, Equatable, Codable {
        public let vocabulary: [CustomVocabularyEntry]
        public let defaultIntensity: Double?

        public init(vocabulary: [CustomVocabularyEntry], defaultIntensity: Double? = nil) {
            self.vocabulary = vocabulary
            self.defaultIntensity = defaultIntensity
        }

        private enum CodingKeys: String, CodingKey {
            case vocabulary
            case defaultIntensity
        }
    }

    public struct CodeSwitchingConfig: Sendable, Equatable, Codable {
        public let languages: [String]?

        public init(languages: [String]? = nil) {
            self.languages = languages
        }
    }

    public struct CallbackConfig: Sendable, Equatable, Codable {
        public enum Method: String, Sendable, Codable {
            case post = "POST"
            case put = "PUT"
        }

        public let url: String
        public let method: Method?

        public init(url: String, method: Method? = nil) {
            self.url = url
            self.method = method
        }
    }

    public struct SubtitlesConfig: Sendable, Equatable, Codable {
        public enum Format: String, Sendable, Codable {
            case srt
            case vtt
        }

        public enum Style: String, Sendable, Codable {
            case `default`
            case compliance
        }

        public let formats: [Format]?
        public let minimumDuration: Double?
        public let maximumDuration: Double?
        public let maximumCharactersPerRow: Int?
        public let maximumRowsPerCaption: Int?
        public let style: Style?

        public init(
            formats: [Format]? = nil,
            minimumDuration: Double? = nil,
            maximumDuration: Double? = nil,
            maximumCharactersPerRow: Int? = nil,
            maximumRowsPerCaption: Int? = nil,
            style: Style? = nil
        ) {
            self.formats = formats
            self.minimumDuration = minimumDuration
            self.maximumDuration = maximumDuration
            self.maximumCharactersPerRow = maximumCharactersPerRow
            self.maximumRowsPerCaption = maximumRowsPerCaption
            self.style = style
        }

        private enum CodingKeys: String, CodingKey {
            case formats
            case minimumDuration
            case maximumDuration
            case maximumCharactersPerRow
            case maximumRowsPerCaption
            case style
        }
    }

    public struct DiarizationConfig: Sendable, Equatable, Codable {
        public let numberOfSpeakers: Int?
        public let minSpeakers: Int?
        public let maxSpeakers: Int?
        public let enhanced: Bool?

        public init(
            numberOfSpeakers: Int? = nil,
            minSpeakers: Int? = nil,
            maxSpeakers: Int? = nil,
            enhanced: Bool? = nil
        ) {
            self.numberOfSpeakers = numberOfSpeakers
            self.minSpeakers = minSpeakers
            self.maxSpeakers = maxSpeakers
            self.enhanced = enhanced
        }
    }

    public struct TranslationConfig: Sendable, Equatable, Codable {
        public enum Model: String, Sendable, Codable {
            case base
            case enhanced
        }

        public let targetLanguages: [String]
        public let model: Model?
        public let matchOriginalUtterances: Bool?

        public init(
            targetLanguages: [String],
            model: Model? = nil,
            matchOriginalUtterances: Bool? = nil
        ) {
            self.targetLanguages = targetLanguages
            self.model = model
            self.matchOriginalUtterances = matchOriginalUtterances
        }

        private enum CodingKeys: String, CodingKey {
            case targetLanguages
            case model
            case matchOriginalUtterances
        }
    }

    public struct SummarizationConfig: Sendable, Equatable, Codable {
        public enum SummaryType: String, Sendable, Codable {
            case general
            case bulletPoints = "bullet_points"
            case concise
        }

        public let type: SummaryType?

        public init(type: SummaryType? = nil) {
            self.type = type
        }
    }

    public struct CustomSpellingConfig: Sendable, Equatable, Codable {
        public let spellingDictionary: [String: [String]]

        public init(spellingDictionary: [String: [String]]) {
            self.spellingDictionary = spellingDictionary
        }
    }

    public struct StructuredDataExtractionConfig: Sendable, Equatable, Codable {
        public let classes: [String]

        public init(classes: [String]) {
            self.classes = classes
        }
    }

    public struct AudioToLLMConfig: Sendable, Equatable, Codable {
        public let prompts: [String]

        public init(prompts: [String]) {
            self.prompts = prompts
        }
    }

    public var contextPrompt: String?
    public var customVocabulary: CustomVocabulary?
    public var customVocabularyConfig: CustomVocabularyConfig?
    public var detectLanguage: Bool?
    public var enableCodeSwitching: Bool?
    public var codeSwitchingConfig: CodeSwitchingConfig?
    public var language: String?
    public var callback: Bool?
    public var callbackConfig: CallbackConfig?
    public var subtitles: Bool?
    public var subtitlesConfig: SubtitlesConfig?
    public var diarization: Bool?
    public var diarizationConfig: DiarizationConfig?
    public var translation: Bool?
    public var translationConfig: TranslationConfig?
    public var summarization: Bool?
    public var summarizationConfig: SummarizationConfig?
    public var moderation: Bool?
    public var namedEntityRecognition: Bool?
    public var chapterization: Bool?
    public var nameConsistency: Bool?
    public var customSpelling: Bool?
    public var customSpellingConfig: CustomSpellingConfig?
    public var structuredDataExtraction: Bool?
    public var structuredDataExtractionConfig: StructuredDataExtractionConfig?
    public var sentimentAnalysis: Bool?
    public var audioToLlm: Bool?
    public var audioToLlmConfig: AudioToLLMConfig?
    public var customMetadata: [String: JSONValue]?
    public var sentences: Bool?
    public var displayMode: Bool?
    public var punctuationEnhanced: Bool?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case contextPrompt
        case customVocabulary
        case customVocabularyConfig
        case detectLanguage
        case enableCodeSwitching
        case codeSwitchingConfig
        case language
        case callback
        case callbackConfig
        case subtitles
        case subtitlesConfig
        case diarization
        case diarizationConfig
        case translation
        case translationConfig
        case summarization
        case summarizationConfig
        case moderation
        case namedEntityRecognition
        case chapterization
        case nameConsistency
        case customSpelling
        case customSpellingConfig
        case structuredDataExtraction
        case structuredDataExtractionConfig
        case sentimentAnalysis
        case audioToLlm
        case audioToLlmConfig
        case customMetadata
        case sentences
        case displayMode
        case punctuationEnhanced
    }
}

private let gladiaTranscriptionOptionsSchemaJSON: JSONValue = .object([
    "type": .string("object")
])

public let gladiaTranscriptionOptionsSchema = FlexibleSchema(
    Schema<GladiaTranscriptionOptions>.codable(
        GladiaTranscriptionOptions.self,
        jsonSchema: gladiaTranscriptionOptionsSchemaJSON
    )
)
