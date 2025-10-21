import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GoogleGenerativeAIResponseModality: String, Sendable, Equatable {
    case text = "TEXT"
    case image = "IMAGE"
}

public struct GoogleGenerativeAIThinkingConfig: Sendable, Equatable {
    public var thinkingBudget: Double?
    public var includeThoughts: Bool?

    public init(thinkingBudget: Double? = nil, includeThoughts: Bool? = nil) {
        self.thinkingBudget = thinkingBudget
        self.includeThoughts = includeThoughts
    }
}

public enum GoogleGenerativeAISafetyCategory: String, Sendable, Equatable {
    case harmCategoryUnspecified = "HARM_CATEGORY_UNSPECIFIED"
    case hateSpeech = "HARM_CATEGORY_HATE_SPEECH"
    case dangerousContent = "HARM_CATEGORY_DANGEROUS_CONTENT"
    case harassment = "HARM_CATEGORY_HARASSMENT"
    case sexuallyExplicit = "HARM_CATEGORY_SEXUALLY_EXPLICIT"
    case civicIntegrity = "HARM_CATEGORY_CIVIC_INTEGRITY"
}

public enum GoogleGenerativeAISafetyThreshold: String, Sendable, Equatable {
    case unspecified = "HARM_BLOCK_THRESHOLD_UNSPECIFIED"
    case blockLowAndAbove = "BLOCK_LOW_AND_ABOVE"
    case blockMediumAndAbove = "BLOCK_MEDIUM_AND_ABOVE"
    case blockOnlyHigh = "BLOCK_ONLY_HIGH"
    case blockNone = "BLOCK_NONE"
    case off = "OFF"
}

public struct GoogleGenerativeAISafetySetting: Sendable, Equatable {
    public var category: GoogleGenerativeAISafetyCategory
    public var threshold: GoogleGenerativeAISafetyThreshold

    public init(
        category: GoogleGenerativeAISafetyCategory,
        threshold: GoogleGenerativeAISafetyThreshold
    ) {
        self.category = category
        self.threshold = threshold
    }
}

public enum GoogleGenerativeAIMediaResolution: String, Sendable, Equatable {
    case unspecified = "MEDIA_RESOLUTION_UNSPECIFIED"
    case low = "MEDIA_RESOLUTION_LOW"
    case medium = "MEDIA_RESOLUTION_MEDIUM"
    case high = "MEDIA_RESOLUTION_HIGH"
}

public enum GoogleGenerativeAIImageConfigAspectRatio: String, Sendable, Equatable {
    case oneToOne = "1:1"
    case twoToThree = "2:3"
    case threeToTwo = "3:2"
    case threeToFour = "3:4"
    case fourToThree = "4:3"
    case fourToFive = "4:5"
    case fiveToFour = "5:4"
    case nineToSixteen = "9:16"
    case sixteenToNine = "16:9"
    case twentyOneToNine = "21:9"
}

public struct GoogleGenerativeAIImageConfig: Sendable, Equatable {
    public var aspectRatio: GoogleGenerativeAIImageConfigAspectRatio?

    public init(aspectRatio: GoogleGenerativeAIImageConfigAspectRatio? = nil) {
        self.aspectRatio = aspectRatio
    }
}

public struct GoogleGenerativeAIProviderOptions: Sendable, Equatable {
    public var responseModalities: [GoogleGenerativeAIResponseModality]?
    public var thinkingConfig: GoogleGenerativeAIThinkingConfig?
    public var cachedContent: String?
    public var structuredOutputs: Bool?
    public var safetySettings: [GoogleGenerativeAISafetySetting]?
    public var threshold: GoogleGenerativeAISafetyThreshold?
    public var audioTimestamp: Bool?
    public var labels: [String: String]?
    public var mediaResolution: GoogleGenerativeAIMediaResolution?
    public var imageConfig: GoogleGenerativeAIImageConfig?

    public init(
        responseModalities: [GoogleGenerativeAIResponseModality]? = nil,
        thinkingConfig: GoogleGenerativeAIThinkingConfig? = nil,
        cachedContent: String? = nil,
        structuredOutputs: Bool? = nil,
        safetySettings: [GoogleGenerativeAISafetySetting]? = nil,
        threshold: GoogleGenerativeAISafetyThreshold? = nil,
        audioTimestamp: Bool? = nil,
        labels: [String: String]? = nil,
        mediaResolution: GoogleGenerativeAIMediaResolution? = nil,
        imageConfig: GoogleGenerativeAIImageConfig? = nil
    ) {
        self.responseModalities = responseModalities
        self.thinkingConfig = thinkingConfig
        self.cachedContent = cachedContent
        self.structuredOutputs = structuredOutputs
        self.safetySettings = safetySettings
        self.threshold = threshold
        self.audioTimestamp = audioTimestamp
        self.labels = labels
        self.mediaResolution = mediaResolution
        self.imageConfig = imageConfig
    }
}

private let googleProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let googleGenerativeAIProviderOptionsSchema = FlexibleSchema(
    Schema<GoogleGenerativeAIProviderOptions>(
        jsonSchemaResolver: { googleProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "google",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var responseModalities: [GoogleGenerativeAIResponseModality]? = nil
                if let modalitiesValue = dict["responseModalities"], modalitiesValue != .null {
                    guard case .array(let array) = modalitiesValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "responseModalities must be an array"
                        )
                        return .failure(error: TypeValidationError.wrap(value: modalitiesValue, cause: error))
                    }

                    responseModalities = try array.map { element -> GoogleGenerativeAIResponseModality in
                        guard case .string(let raw) = element, let modality = GoogleGenerativeAIResponseModality(rawValue: raw) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "responseModalities entries must be 'TEXT' or 'IMAGE'"
                            )
                            throw TypeValidationError.wrap(value: element, cause: error)
                        }
                        return modality
                    }
                }

                var thinkingConfig: GoogleGenerativeAIThinkingConfig? = nil
                if let thinkingValue = dict["thinkingConfig"], thinkingValue != .null {
                    guard case .object(let thinkingDict) = thinkingValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "thinkingConfig must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    var includeThoughts: Bool? = nil
                    if let includeValue = thinkingDict["includeThoughts"], includeValue != .null {
                        guard case .bool(let boolValue) = includeValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "thinkingConfig.includeThoughts must be a boolean"
                            )
                            return .failure(error: TypeValidationError.wrap(value: includeValue, cause: error))
                        }
                        includeThoughts = boolValue
                    }

                    var budget: Double? = nil
                    if let budgetValue = thinkingDict["thinkingBudget"], budgetValue != .null {
                        switch budgetValue {
                        case .number(let number):
                            budget = number
                        default:
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "thinkingConfig.thinkingBudget must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: budgetValue, cause: error))
                        }
                    }

                    thinkingConfig = GoogleGenerativeAIThinkingConfig(
                        thinkingBudget: budget,
                        includeThoughts: includeThoughts
                    )
                }

                func optionalString(_ key: String, in dictionary: [String: JSONValue]) throws -> String? {
                    guard let value = dictionary[key], value != .null else { return nil }
                    guard case .string(let string) = value else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "\(key) must be a string"
                        )
                        throw TypeValidationError.wrap(value: value, cause: error)
                    }
                    return string
                }

                var safetySettings: [GoogleGenerativeAISafetySetting]? = nil
                if let safetyValue = dict["safetySettings"], safetyValue != .null {
                    guard case .array(let array) = safetyValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "safetySettings must be an array"
                        )
                        return .failure(error: TypeValidationError.wrap(value: safetyValue, cause: error))
                    }

                    safetySettings = try array.map { element -> GoogleGenerativeAISafetySetting in
                        guard case .object(let object) = element else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "each safety setting must be an object"
                            )
                            throw TypeValidationError.wrap(value: element, cause: error)
                        }

                        let categoryString = try optionalString("category", in: object) ?? ""
                        guard let category = GoogleGenerativeAISafetyCategory(rawValue: categoryString) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "invalid safetySettings.category value"
                            )
                            throw TypeValidationError.wrap(value: object["category"] ?? .null, cause: error)
                        }

                        let thresholdString = try optionalString("threshold", in: object) ?? ""
                        guard let threshold = GoogleGenerativeAISafetyThreshold(rawValue: thresholdString) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "invalid safetySettings.threshold value"
                            )
                            throw TypeValidationError.wrap(value: object["threshold"] ?? .null, cause: error)
                        }

                        return GoogleGenerativeAISafetySetting(
                            category: category,
                            threshold: threshold
                        )
                    }
                }

                var cachedContent: String? = nil
                if let cachedValue = dict["cachedContent"], cachedValue != .null {
                    guard case .string(let cachedString) = cachedValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "cachedContent must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: cachedValue, cause: error))
                    }
                    cachedContent = cachedString
                }

                var structuredOutputs: Bool? = nil
                if let structuredValue = dict["structuredOutputs"], structuredValue != .null {
                    guard case .bool(let boolValue) = structuredValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "structuredOutputs must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: structuredValue, cause: error))
                    }
                    structuredOutputs = boolValue
                }

                var threshold: GoogleGenerativeAISafetyThreshold? = nil
                if let thresholdValue = dict["threshold"], thresholdValue != .null {
                    guard case .string(let thresholdRaw) = thresholdValue,
                          let parsed = GoogleGenerativeAISafetyThreshold(rawValue: thresholdRaw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "threshold must be a valid enum value"
                        )
                        return .failure(error: TypeValidationError.wrap(value: thresholdValue, cause: error))
                    }
                    threshold = parsed
                }

                var audioTimestamp: Bool? = nil
                if let audioValue = dict["audioTimestamp"], audioValue != .null {
                    guard case .bool(let boolValue) = audioValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "audioTimestamp must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: audioValue, cause: error))
                    }
                    audioTimestamp = boolValue
                }

                var labels: [String: String]? = nil
                if let labelsValue = dict["labels"], labelsValue != .null {
                    guard case .object(let labelsDict) = labelsValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "labels must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: labelsValue, cause: error))
                    }

                    var parsed: [String: String] = [:]
                    for (key, value) in labelsDict {
                        guard case .string(let stringValue) = value else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "label values must be strings"
                            )
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        parsed[key] = stringValue
                    }
                    labels = parsed
                }

                var mediaResolution: GoogleGenerativeAIMediaResolution? = nil
                if let mediaValue = dict["mediaResolution"], mediaValue != .null {
                    guard case .string(let mediaRaw) = mediaValue,
                          let parsed = GoogleGenerativeAIMediaResolution(rawValue: mediaRaw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "mediaResolution must be a valid enum value"
                        )
                        return .failure(error: TypeValidationError.wrap(value: mediaValue, cause: error))
                    }
                    mediaResolution = parsed
                }

                var imageConfig: GoogleGenerativeAIImageConfig? = nil
                if let imageConfigValue = dict["imageConfig"], imageConfigValue != .null {
                    guard case .object(let imageConfigDict) = imageConfigValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "imageConfig must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: imageConfigValue, cause: error))
                    }

                    var aspectRatio: GoogleGenerativeAIImageConfigAspectRatio? = nil
                    if let aspectValue = imageConfigDict["aspectRatio"], aspectValue != .null {
                        guard case .string(let aspectRaw) = aspectValue,
                              let parsed = GoogleGenerativeAIImageConfigAspectRatio(rawValue: aspectRaw) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "imageConfig.aspectRatio must be a supported ratio"
                            )
                            return .failure(error: TypeValidationError.wrap(value: aspectValue, cause: error))
                        }
                        aspectRatio = parsed
                    }

                    imageConfig = GoogleGenerativeAIImageConfig(aspectRatio: aspectRatio)
                }

                let options = GoogleGenerativeAIProviderOptions(
                    responseModalities: responseModalities,
                    thinkingConfig: thinkingConfig,
                    cachedContent: cachedContent,
                    structuredOutputs: structuredOutputs,
                    safetySettings: safetySettings,
                    threshold: threshold,
                    audioTimestamp: audioTimestamp,
                    labels: labels,
                    mediaResolution: mediaResolution,
                    imageConfig: imageConfig
                )

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

extension GoogleGenerativeAIProviderOptions {
    public func toDictionary() -> [String: Any] {
        var result: [String: Any] = [:]

        if let responseModalities {
            result["responseModalities"] = responseModalities.map { $0.rawValue }
        }

        if let thinkingConfig {
            var thinking: [String: Any] = [:]
            if let includeThoughts = thinkingConfig.includeThoughts {
                thinking["includeThoughts"] = includeThoughts
            }
            if let budget = thinkingConfig.thinkingBudget {
                thinking["thinkingBudget"] = budget
            }
            if !thinking.isEmpty {
                result["thinkingConfig"] = thinking
            }
        }

        if let cachedContent {
            result["cachedContent"] = cachedContent
        }

        if let structuredOutputs {
            result["structuredOutputs"] = structuredOutputs
        }

        if let safetySettings, !safetySettings.isEmpty {
            result["safetySettings"] = safetySettings.map { setting in
                [
                    "category": setting.category.rawValue,
                    "threshold": setting.threshold.rawValue
                ]
            }
        }

        if let threshold {
            result["threshold"] = threshold.rawValue
        }

        if let audioTimestamp {
            result["audioTimestamp"] = audioTimestamp
        }

        if let labels, !labels.isEmpty {
            result["labels"] = labels
        }

        if let mediaResolution {
            result["mediaResolution"] = mediaResolution.rawValue
        }

        if let imageConfig {
            var config: [String: Any] = [:]
            if let aspectRatio = imageConfig.aspectRatio {
                config["aspectRatio"] = aspectRatio.rawValue
            }
            if !config.isEmpty {
                result["imageConfig"] = config
            }
        }

        return result
    }
}
