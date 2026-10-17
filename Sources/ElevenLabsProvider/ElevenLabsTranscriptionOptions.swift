import Foundation
import AISDKProviderUtils

public struct ElevenLabsTranscriptionModelOptions: Codable, Sendable {
    public enum TimestampsGranularity: String, Codable, Sendable { case none, word, character }
    public enum FileFormat: String, Codable, Sendable { case pcm_s16le_16, other }

    public struct Streaming: Codable, Sendable {
        public enum CommitStrategy: String, Codable, Sendable { case manual, vad }

        public var commitStrategy: CommitStrategy?
        public var enableLogging: Bool?
        public var filterBackgroundAudio: Bool?
        public var includeLanguageDetection: Bool?
        public var includeTimestamps: Bool?
        public var keyterms: [String]?
        public var minSilenceDurationMs: Int?
        public var minSpeechDurationMs: Int?
        public var noVerbatim: Bool?
        public var previousText: String?
        public var secondaryLanguages: [String]?
        public var vadSilenceThresholdSecs: Double?
        public var vadThreshold: Double?

        public init(
            commitStrategy: CommitStrategy? = nil,
            enableLogging: Bool? = nil,
            filterBackgroundAudio: Bool? = nil,
            includeLanguageDetection: Bool? = nil,
            includeTimestamps: Bool? = nil,
            keyterms: [String]? = nil,
            minSilenceDurationMs: Int? = nil,
            minSpeechDurationMs: Int? = nil,
            noVerbatim: Bool? = nil,
            previousText: String? = nil,
            secondaryLanguages: [String]? = nil,
            vadSilenceThresholdSecs: Double? = nil,
            vadThreshold: Double? = nil
        ) {
            self.commitStrategy = commitStrategy
            self.enableLogging = enableLogging
            self.filterBackgroundAudio = filterBackgroundAudio
            self.includeLanguageDetection = includeLanguageDetection
            self.includeTimestamps = includeTimestamps
            self.keyterms = keyterms
            self.minSilenceDurationMs = minSilenceDurationMs
            self.minSpeechDurationMs = minSpeechDurationMs
            self.noVerbatim = noVerbatim
            self.previousText = previousText
            self.secondaryLanguages = secondaryLanguages
            self.vadSilenceThresholdSecs = vadSilenceThresholdSecs
            self.vadThreshold = vadThreshold
        }

        private enum CodingKeys: String, CodingKey {
            case commitStrategy, enableLogging, filterBackgroundAudio, includeLanguageDetection, includeTimestamps
            case keyterms, minSilenceDurationMs, minSpeechDurationMs, noVerbatim, previousText, secondaryLanguages
            case vadSilenceThresholdSecs, vadThreshold
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commitStrategy = try container.decodeIfPresent(CommitStrategy.self, forKey: .commitStrategy)
            enableLogging = try container.decodeIfPresent(Bool.self, forKey: .enableLogging)
            filterBackgroundAudio = try container.decodeIfPresent(Bool.self, forKey: .filterBackgroundAudio)
            includeLanguageDetection = try container.decodeIfPresent(Bool.self, forKey: .includeLanguageDetection)
            includeTimestamps = try container.decodeIfPresent(Bool.self, forKey: .includeTimestamps)
            keyterms = try container.decodeIfPresent([String].self, forKey: .keyterms)
            minSilenceDurationMs = try container.decodeIfPresent(Int.self, forKey: .minSilenceDurationMs)
            minSpeechDurationMs = try container.decodeIfPresent(Int.self, forKey: .minSpeechDurationMs)
            noVerbatim = try container.decodeIfPresent(Bool.self, forKey: .noVerbatim)
            previousText = try container.decodeIfPresent(String.self, forKey: .previousText)
            secondaryLanguages = try container.decodeIfPresent([String].self, forKey: .secondaryLanguages)
            vadSilenceThresholdSecs = try container.decodeIfPresent(Double.self, forKey: .vadSilenceThresholdSecs)
            vadThreshold = try container.decodeIfPresent(Double.self, forKey: .vadThreshold)
            if let keyterms, keyterms.count > 50 || keyterms.contains(where: { $0.utf16.count > 20 }) {
                throw DecodingError.dataCorruptedError(forKey: .keyterms, in: container, debugDescription: "At most 50 keyterms of at most 20 characters are supported")
            }
            for value in [minSilenceDurationMs, minSpeechDurationMs].compactMap({ $0 }) where !(50...2000).contains(value) {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Speech and silence durations must be between 50 and 2000 ms"))
            }
            if let value = vadSilenceThresholdSecs, !(0.3...3).contains(value) {
                throw DecodingError.dataCorruptedError(forKey: .vadSilenceThresholdSecs, in: container, debugDescription: "VAD silence threshold must be between 0.3 and 3 seconds")
            }
            if let value = vadThreshold, !(0.1...0.9).contains(value) {
                throw DecodingError.dataCorruptedError(forKey: .vadThreshold, in: container, debugDescription: "VAD threshold must be between 0.1 and 0.9")
            }
        }
    }

    public var languageCode: String?
    public var tagAudioEvents: Bool?
    public var numSpeakers: Int?
    public var timestampsGranularity: TimestampsGranularity?
    public var diarize: Bool?
    public var fileFormat: FileFormat?
    public var streaming: Streaming?

    public init(
        languageCode: String? = nil,
        tagAudioEvents: Bool? = nil,
        numSpeakers: Int? = nil,
        timestampsGranularity: TimestampsGranularity? = nil,
        diarize: Bool? = nil,
        fileFormat: FileFormat? = nil,
        streaming: Streaming? = nil
    ) {
        self.languageCode = languageCode
        self.tagAudioEvents = tagAudioEvents
        self.numSpeakers = numSpeakers
        self.timestampsGranularity = timestampsGranularity
        self.diarize = diarize
        self.fileFormat = fileFormat
        self.streaming = streaming
    }

    private enum CodingKeys: String, CodingKey {
        case languageCode, tagAudioEvents, numSpeakers, timestampsGranularity, diarize, fileFormat, streaming
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        tagAudioEvents = try container.contains(.tagAudioEvents) ? container.decodeIfPresent(Bool.self, forKey: .tagAudioEvents) : true
        numSpeakers = try container.decodeIfPresent(Int.self, forKey: .numSpeakers)
        timestampsGranularity = try container.contains(.timestampsGranularity) ? container.decodeIfPresent(TimestampsGranularity.self, forKey: .timestampsGranularity) : .word
        diarize = try container.contains(.diarize) ? container.decodeIfPresent(Bool.self, forKey: .diarize) : true
        fileFormat = try container.contains(.fileFormat) ? container.decodeIfPresent(FileFormat.self, forKey: .fileFormat) : .other
        streaming = try container.decodeIfPresent(Streaming.self, forKey: .streaming)
        if let value = numSpeakers, !(1...32).contains(value) {
            throw DecodingError.dataCorruptedError(forKey: .numSpeakers, in: container, debugDescription: "numSpeakers must be between 1 and 32")
        }
    }
}

let elevenLabsTranscriptionModelOptionsSchema = FlexibleSchema(
    Schema<ElevenLabsTranscriptionModelOptions>.codable(
        ElevenLabsTranscriptionModelOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
