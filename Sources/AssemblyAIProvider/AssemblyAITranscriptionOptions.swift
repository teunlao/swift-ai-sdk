import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/assemblyai/src/assemblyai-transcription-model.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct AssemblyAITranscriptionOptions: Sendable, Equatable {
    public struct CustomSpelling: Sendable, Equatable {
        public var from: [String]
        public var to: String

        public init(from: [String], to: String) {
            self.from = from
            self.to = to
        }
    }

    public var audioEndAt: Int?
    public var audioStartFrom: Int?
    public var autoChapters: Bool?
    public var autoHighlights: Bool?
    public var boostParam: String?
    public var contentSafety: Bool?
    public var contentSafetyConfidence: Int?
    public var customSpelling: [CustomSpelling]?
    public var disfluencies: Bool?
    public var entityDetection: Bool?
    public var filterProfanity: Bool?
    public var formatText: Bool?
    public var iabCategories: Bool?
    public var languageCode: String?
    public var languageConfidenceThreshold: Double?
    public var languageDetection: Bool?
    public var multichannel: Bool?
    public var punctuate: Bool?
    public var redactPii: Bool?
    public var redactPiiAudio: Bool?
    public var redactPiiAudioQuality: String?
    public var redactPiiPolicies: [String]?
    public var redactPiiSub: String?
    public var sentimentAnalysis: Bool?
    public var speakerLabels: Bool?
    public var speakersExpected: Int?
    public var speechThreshold: Double?
    public var summarization: Bool?
    public var summaryModel: String?
    public var summaryType: String?
    public var webhookAuthHeaderName: String?
    public var webhookAuthHeaderValue: String?
    public var webhookUrl: String?
    public var wordBoost: [String]?

    public init() {}
}

private let assemblyaiOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let assemblyaiTranscriptionOptionsSchema = FlexibleSchema(
    Schema<AssemblyAITranscriptionOptions>(
        jsonSchemaResolver: { assemblyaiOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "assemblyai",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = AssemblyAITranscriptionOptions()

                if let raw = dict["audioEndAt"], raw != .null {
                    guard case .number(let number) = raw, number.rounded(.towardZero) == number else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "audioEndAt must be an integer")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.audioEndAt = Int(number)
                }

                if let raw = dict["audioStartFrom"], raw != .null {
                    guard case .number(let number) = raw, number.rounded(.towardZero) == number else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "audioStartFrom must be an integer")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.audioStartFrom = Int(number)
                }

                if let raw = dict["autoChapters"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "autoChapters must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.autoChapters = flag
                }

                if let raw = dict["autoHighlights"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "autoHighlights must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.autoHighlights = flag
                }

                if let raw = dict["boostParam"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "boostParam must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.boostParam = stringValue
                }

                if let raw = dict["contentSafety"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "contentSafety must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.contentSafety = flag
                }

                if let raw = dict["contentSafetyConfidence"], raw != .null {
                    guard case .number(let number) = raw, number.rounded(.towardZero) == number else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "contentSafetyConfidence must be an integer")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    let intValue = Int(number)
                    if intValue < 25 || intValue > 100 {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "contentSafetyConfidence must be between 25 and 100")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.contentSafetyConfidence = intValue
                }

                if let raw = dict["customSpelling"], raw != .null {
                    guard case .array(let entries) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "customSpelling must be an array")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var spelled: [AssemblyAITranscriptionOptions.CustomSpelling] = []
                    spelled.reserveCapacity(entries.count)
                    for entry in entries {
                        guard case .object(let object) = entry else {
                            let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "customSpelling entries must be objects")
                            return .failure(error: TypeValidationError.wrap(value: entry, cause: error))
                        }
                        guard let fromRaw = object["from"], case .array(let fromArray) = fromRaw else {
                            let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "customSpelling.from must be an array of strings")
                            return .failure(error: TypeValidationError.wrap(value: object["from"] ?? .null, cause: error))
                        }
                        var from: [String] = []
                        from.reserveCapacity(fromArray.count)
                        for component in fromArray {
                            guard case .string(let stringValue) = component else {
                                let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "customSpelling.from must be an array of strings")
                                return .failure(error: TypeValidationError.wrap(value: component, cause: error))
                            }
                            from.append(stringValue)
                        }
                        guard let toRaw = object["to"], case .string(let toValue) = toRaw else {
                            let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "customSpelling.to must be a string")
                            return .failure(error: TypeValidationError.wrap(value: object["to"] ?? .null, cause: error))
                        }
                        spelled.append(.init(from: from, to: toValue))
                    }
                    options.customSpelling = spelled
                }

                if let raw = dict["disfluencies"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "disfluencies must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.disfluencies = flag
                }

                if let raw = dict["entityDetection"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "entityDetection must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.entityDetection = flag
                }

                if let raw = dict["filterProfanity"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "filterProfanity must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.filterProfanity = flag
                }

                if let raw = dict["formatText"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "formatText must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.formatText = flag
                }

                if let raw = dict["iabCategories"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "iabCategories must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.iabCategories = flag
                }

                if let raw = dict["languageCode"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "languageCode must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.languageCode = stringValue
                }

                if let raw = dict["languageConfidenceThreshold"], raw != .null {
                    guard case .number(let number) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "languageConfidenceThreshold must be a number")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.languageConfidenceThreshold = number
                }

                if let raw = dict["languageDetection"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "languageDetection must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.languageDetection = flag
                }

                if let raw = dict["multichannel"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "multichannel must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.multichannel = flag
                }

                if let raw = dict["punctuate"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "punctuate must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.punctuate = flag
                }

                if let raw = dict["redactPii"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "redactPii must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.redactPii = flag
                }

                if let raw = dict["redactPiiAudio"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "redactPiiAudio must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.redactPiiAudio = flag
                }

                if let raw = dict["redactPiiAudioQuality"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "redactPiiAudioQuality must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.redactPiiAudioQuality = stringValue
                }

                if let raw = dict["redactPiiPolicies"], raw != .null {
                    guard case .array(let array) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "redactPiiPolicies must be an array of strings")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var values: [String] = []
                    values.reserveCapacity(array.count)
                    for item in array {
                        guard case .string(let stringValue) = item else {
                            let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "redactPiiPolicies must be an array of strings")
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        values.append(stringValue)
                    }
                    options.redactPiiPolicies = values
                }

                if let raw = dict["redactPiiSub"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "redactPiiSub must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.redactPiiSub = stringValue
                }

                if let raw = dict["sentimentAnalysis"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "sentimentAnalysis must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.sentimentAnalysis = flag
                }

                if let raw = dict["speakerLabels"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "speakerLabels must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.speakerLabels = flag
                }

                if let raw = dict["speakersExpected"], raw != .null {
                    guard case .number(let number) = raw, number.rounded(.towardZero) == number else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "speakersExpected must be an integer")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.speakersExpected = Int(number)
                }

                if let raw = dict["speechThreshold"], raw != .null {
                    guard case .number(let number) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "speechThreshold must be a number")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    if number < 0 || number > 1 {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "speechThreshold must be between 0 and 1")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.speechThreshold = number
                }

                if let raw = dict["summarization"], raw != .null {
                    guard case .bool(let flag) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "summarization must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.summarization = flag
                }

                if let raw = dict["summaryModel"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "summaryModel must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.summaryModel = stringValue
                }

                if let raw = dict["summaryType"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "summaryType must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.summaryType = stringValue
                }

                if let raw = dict["webhookAuthHeaderName"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "webhookAuthHeaderName must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.webhookAuthHeaderName = stringValue
                }

                if let raw = dict["webhookAuthHeaderValue"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "webhookAuthHeaderValue must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.webhookAuthHeaderValue = stringValue
                }

                if let raw = dict["webhookUrl"], raw != .null {
                    guard case .string(let stringValue) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "webhookUrl must be a string")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    options.webhookUrl = stringValue
                }

                if let raw = dict["wordBoost"], raw != .null {
                    guard case .array(let array) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "wordBoost must be an array of strings")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var values: [String] = []
                    values.reserveCapacity(array.count)
                    for item in array {
                        guard case .string(let stringValue) = item else {
                            let error = SchemaValidationIssuesError(vendor: "assemblyai", issues: "wordBoost must be an array of strings")
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        values.append(stringValue)
                    }
                    options.wordBoost = values
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
