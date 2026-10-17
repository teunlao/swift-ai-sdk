import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AssemblyAITranscriptionModelOptions: Codable, Sendable, Equatable {
    public struct CustomSpelling: Codable, Sendable, Equatable {
        public var from: [String]
        public var to: String
        public init(from: [String], to: String) { self.from = from; self.to = to }
    }
    public struct SpeakerOptions: Codable, Sendable, Equatable {
        public var minSpeakersExpected: Int?
        public var maxSpeakersExpected: Int?
        public init(minSpeakersExpected: Int? = nil, maxSpeakersExpected: Int? = nil) {
            self.minSpeakersExpected = minSpeakersExpected; self.maxSpeakersExpected = maxSpeakersExpected
        }
    }
    public struct LanguageDetectionOptions: Codable, Sendable, Equatable {
        public var expectedLanguages: [String]?
        public var fallbackLanguage: String?
        public var codeSwitching: Bool?
        public var codeSwitchingConfidenceThreshold: Double?
        public init(expectedLanguages: [String]? = nil, fallbackLanguage: String? = nil, codeSwitching: Bool? = nil, codeSwitchingConfidenceThreshold: Double? = nil) {
            self.expectedLanguages = expectedLanguages; self.fallbackLanguage = fallbackLanguage
            self.codeSwitching = codeSwitching; self.codeSwitchingConfidenceThreshold = codeSwitchingConfidenceThreshold
        }
    }
    public struct RedactPiiAudioOptions: Codable, Sendable, Equatable {
        public enum Method: String, Codable, Sendable { case silence }
        public var returnRedactedNoSpeechAudio: Bool?
        public var overrideAudioRedactionMethod: Method?
        public init(returnRedactedNoSpeechAudio: Bool? = nil, overrideAudioRedactionMethod: Method? = nil) {
            self.returnRedactedNoSpeechAudio = returnRedactedNoSpeechAudio; self.overrideAudioRedactionMethod = overrideAudioRedactionMethod
        }
    }
    public enum RemoveAudioTags: String, Codable, Sendable { case all, speaker }
    public var audioEndAt: Int?
    public var audioStartFrom: Int?
    public var autoChapters: Bool?
    public var autoHighlights: Bool?
    public var boostParam: String?
    public var contentSafety: Bool?
    public var contentSafetyConfidence: Int?
    public var customSpelling: [CustomSpelling]?
    public var disfluencies: Bool?
    public var domain: String?
    public var entityDetection: Bool?
    public var filterProfanity: Bool?
    public var formatText: Bool?
    public var iabCategories: Bool?
    public var keytermsPrompt: [String]?
    public var languageCode: String?
    public var languageConfidenceThreshold: Double?
    public var languageDetection: Bool?
    public var languageDetectionOptions: LanguageDetectionOptions?
    public var multichannel: Bool?
    public var prompt: String?
    public var punctuate: Bool?
    public var redactPii: Bool?
    public var redactPiiAudio: Bool?
    public var redactPiiAudioOptions: RedactPiiAudioOptions?
    public var redactPiiAudioQuality: String?
    public var redactPiiPolicies: [String]?
    public var redactPiiReturnUnredacted: Bool?
    public var redactPiiSub: String?
    public var redactStaticEntities: [String: [String]]?
    public var removeAudioTags: RemoveAudioTags?
    public var sentimentAnalysis: Bool?
    public var speakerLabels: Bool?
    public var speakerOptions: SpeakerOptions?
    public var speakersExpected: Int?
    public var speechThreshold: Double?
    public var summarization: Bool?
    public var summaryModel: String?
    public var summaryType: String?
    public var temperature: Double?
    public var webhookAuthHeaderName: String?
    public var webhookAuthHeaderValue: String?
    public var webhookUrl: String?
    public var wordBoost: [String]?
    public init() {}

    func validate() throws {
        for value in [audioEndAt, audioStartFrom, speakersExpected, speakerOptions?.minSpeakersExpected, speakerOptions?.maxSpeakersExpected].compactMap({ $0 }) {
            guard (-9_007_199_254_740_991...9_007_199_254_740_991).contains(value) else {
                throw InvalidArgumentError(argument: "providerOptions", message: "Expected a safe integer")
            }
        }
        if let confidence = contentSafetyConfidence, !(25...100).contains(confidence) {
            throw InvalidArgumentError(argument: "contentSafetyConfidence", message: "Expected a value between 25 and 100")
        }
        for value in [speechThreshold, temperature, languageDetectionOptions?.codeSwitchingConfidenceThreshold].compactMap({ $0 }) {
            guard (0...1).contains(value) else { throw InvalidArgumentError(argument: "providerOptions", message: "Expected a value between 0 and 1") }
        }
    }
}
private let assemblyaiOptionsBaseSchema = Schema<AssemblyAITranscriptionModelOptions>.codable(AssemblyAITranscriptionModelOptions.self, jsonSchema: ["type": "object"])
let assemblyaiTranscriptionModelOptionsSchema = FlexibleSchema(
    Schema<AssemblyAITranscriptionModelOptions>(jsonSchemaResolver: { ["type": "object"] }, validator: { value in
        let parsed = await assemblyaiOptionsBaseSchema.validate(value)
        if case .success(let options) = parsed { try options.validate() }
        return parsed
    })
)
