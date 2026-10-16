import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GoogleResponseModality: String, Sendable, Equatable {
    case text = "TEXT"
    case image = "IMAGE"
    case audio = "AUDIO"
}

public struct GoogleThinkingConfig: Sendable, Equatable {
    public var thinkingBudget: Double?
    public var includeThoughts: Bool?
    public var thinkingLevel: GoogleThinkingLevel?

    public init(
        thinkingBudget: Double? = nil,
        includeThoughts: Bool? = nil,
        thinkingLevel: GoogleThinkingLevel? = nil
    ) {
        self.thinkingBudget = thinkingBudget
        self.includeThoughts = includeThoughts
        self.thinkingLevel = thinkingLevel
    }
}

public enum GoogleThinkingLevel: String, Sendable, Equatable {
    case minimal
    case low
    case medium
    case high
}

public enum GoogleSafetyCategory: String, Sendable, Equatable {
    case harmCategoryUnspecified = "HARM_CATEGORY_UNSPECIFIED"
    case hateSpeech = "HARM_CATEGORY_HATE_SPEECH"
    case dangerousContent = "HARM_CATEGORY_DANGEROUS_CONTENT"
    case harassment = "HARM_CATEGORY_HARASSMENT"
    case sexuallyExplicit = "HARM_CATEGORY_SEXUALLY_EXPLICIT"
    case civicIntegrity = "HARM_CATEGORY_CIVIC_INTEGRITY"
}

public enum GoogleSafetyThreshold: String, Sendable, Equatable {
    case unspecified = "HARM_BLOCK_THRESHOLD_UNSPECIFIED"
    case blockLowAndAbove = "BLOCK_LOW_AND_ABOVE"
    case blockMediumAndAbove = "BLOCK_MEDIUM_AND_ABOVE"
    case blockOnlyHigh = "BLOCK_ONLY_HIGH"
    case blockNone = "BLOCK_NONE"
    case off = "OFF"
}

public struct GoogleSafetySetting: Sendable, Equatable {
    public var category: GoogleSafetyCategory
    public var threshold: GoogleSafetyThreshold

    public init(
        category: GoogleSafetyCategory,
        threshold: GoogleSafetyThreshold
    ) {
        self.category = category
        self.threshold = threshold
    }
}

public enum GoogleMediaResolution: String, Sendable, Equatable {
    case unspecified = "MEDIA_RESOLUTION_UNSPECIFIED"
    case low = "MEDIA_RESOLUTION_LOW"
    case medium = "MEDIA_RESOLUTION_MEDIUM"
    case high = "MEDIA_RESOLUTION_HIGH"
}

public enum GoogleImageConfigAspectRatio: String, Sendable, Equatable {
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
    case oneToEight = "1:8"
    case eightToOne = "8:1"
    case oneToFour = "1:4"
    case fourToOne = "4:1"
}

public enum GoogleImageConfigImageSize: String, Sendable, Equatable {
    case oneK = "1K"
    case twoK = "2K"
    case fourK = "4K"
    case fiveTwelve = "512"
}

public struct GoogleImageConfig: Sendable, Equatable {
    public var aspectRatio: GoogleImageConfigAspectRatio?
    public var imageSize: GoogleImageConfigImageSize?
    public var personGeneration: String?
    public var prominentPeople: String?
    public var imageOutputOptions: JSONValue?

    public init(
        aspectRatio: GoogleImageConfigAspectRatio? = nil,
        imageSize: GoogleImageConfigImageSize? = nil,
        personGeneration: String? = nil,
        prominentPeople: String? = nil,
        imageOutputOptions: JSONValue? = nil
    ) {
        self.aspectRatio = aspectRatio
        self.imageSize = imageSize
        self.personGeneration = personGeneration
        self.prominentPeople = prominentPeople
        self.imageOutputOptions = imageOutputOptions
    }
}

public struct GoogleRetrievalLatLng: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct GoogleRetrievalConfig: Sendable, Equatable {
    public var latLng: GoogleRetrievalLatLng?

    public init(latLng: GoogleRetrievalLatLng? = nil) {
        self.latLng = latLng
    }
}

public struct GoogleLanguageModelOptions: Sendable, Equatable {
    public var responseModalities: [GoogleResponseModality]?
    public var thinkingConfig: GoogleThinkingConfig?
    public var cachedContent: String?
    public var structuredOutputs: Bool?
    public var safetySettings: [GoogleSafetySetting]?
    public var threshold: GoogleSafetyThreshold?
    public var audioTimestamp: Bool?
    public var labels: [String: String]?
    public var mediaResolution: GoogleMediaResolution?
    public var imageConfig: GoogleImageConfig?
    public var retrievalConfig: GoogleRetrievalConfig?
    public var streamFunctionCallArguments: Bool?
    public var serviceTier: String?
    public var continuationToken: String?
    public var sharedRequestType: String?
    public var requestType: String?

    public init(
        responseModalities: [GoogleResponseModality]? = nil,
        thinkingConfig: GoogleThinkingConfig? = nil,
        cachedContent: String? = nil,
        structuredOutputs: Bool? = nil,
        safetySettings: [GoogleSafetySetting]? = nil,
        threshold: GoogleSafetyThreshold? = nil,
        audioTimestamp: Bool? = nil,
        labels: [String: String]? = nil,
        mediaResolution: GoogleMediaResolution? = nil,
        imageConfig: GoogleImageConfig? = nil,
        retrievalConfig: GoogleRetrievalConfig? = nil,
        streamFunctionCallArguments: Bool? = nil,
        serviceTier: String? = nil,
        continuationToken: String? = nil,
        sharedRequestType: String? = nil,
        requestType: String? = nil
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
        self.retrievalConfig = retrievalConfig
        self.streamFunctionCallArguments = streamFunctionCallArguments
        self.serviceTier = serviceTier
        self.continuationToken = continuationToken
        self.sharedRequestType = sharedRequestType
        self.requestType = requestType
    }
}

private let googleProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let googleLanguageModelOptionsSchema = FlexibleSchema(
    Schema<GoogleLanguageModelOptions>(
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

                func rejectNull(
                    _ key: String,
                    in dictionary: [String: JSONValue],
                    issue: String
                ) throws {
                    guard let fieldValue = dictionary[key], fieldValue == .null else {
                        return
                    }

                    let error = SchemaValidationIssuesError(
                        vendor: "google",
                        issues: issue
                    )
                    throw TypeValidationError.wrap(value: fieldValue, cause: error)
                }

                // Upstream zod schema uses `.optional()` (not `.nullish()`) for these fields.
                // `null` must therefore fail validation instead of being treated as missing.
                try rejectNull("responseModalities", in: dict, issue: "responseModalities must be an array")
                try rejectNull("thinkingConfig", in: dict, issue: "thinkingConfig must be an object")
                try rejectNull("cachedContent", in: dict, issue: "cachedContent must be a string")
                try rejectNull("structuredOutputs", in: dict, issue: "structuredOutputs must be a boolean")
                try rejectNull("safetySettings", in: dict, issue: "safetySettings must be an array")
                try rejectNull("threshold", in: dict, issue: "threshold must be a valid enum value")
                try rejectNull("audioTimestamp", in: dict, issue: "audioTimestamp must be a boolean")
                try rejectNull("labels", in: dict, issue: "labels must be an object")
                try rejectNull("mediaResolution", in: dict, issue: "mediaResolution must be a valid enum value")
                try rejectNull("imageConfig", in: dict, issue: "imageConfig must be an object")
                try rejectNull("retrievalConfig", in: dict, issue: "retrievalConfig must be an object")

                var responseModalities: [GoogleResponseModality]? = nil
                if let modalitiesValue = dict["responseModalities"], modalitiesValue != .null {
                    guard case .array(let array) = modalitiesValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "responseModalities must be an array"
                        )
                        return .failure(error: TypeValidationError.wrap(value: modalitiesValue, cause: error))
                    }

                    responseModalities = try array.map { element -> GoogleResponseModality in
                        guard case .string(let raw) = element, let modality = GoogleResponseModality(rawValue: raw) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "responseModalities entries must be 'TEXT' or 'IMAGE'"
                            )
                            throw TypeValidationError.wrap(value: element, cause: error)
                        }
                        return modality
                    }
                }

                var thinkingConfig: GoogleThinkingConfig? = nil
                if let thinkingValue = dict["thinkingConfig"], thinkingValue != .null {
                    guard case .object(let thinkingDict) = thinkingValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "thinkingConfig must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    try rejectNull(
                        "includeThoughts",
                        in: thinkingDict,
                        issue: "thinkingConfig.includeThoughts must be a boolean"
                    )
                    try rejectNull(
                        "thinkingBudget",
                        in: thinkingDict,
                        issue: "thinkingConfig.thinkingBudget must be a number"
                    )
                    try rejectNull(
                        "thinkingLevel",
                        in: thinkingDict,
                        issue: "thinkingConfig.thinkingLevel must be one of 'minimal', 'low', 'medium', 'high'"
                    )

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

                    var thinkingLevel: GoogleThinkingLevel? = nil
                    if let levelValue = thinkingDict["thinkingLevel"], levelValue != .null {
                        guard case .string(let levelRaw) = levelValue,
                              let parsed = GoogleThinkingLevel(rawValue: levelRaw) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "thinkingConfig.thinkingLevel must be one of 'minimal', 'low', 'medium', 'high'"
                            )
                            return .failure(error: TypeValidationError.wrap(value: levelValue, cause: error))
                        }
                        thinkingLevel = parsed
                    }

                    thinkingConfig = GoogleThinkingConfig(
                        thinkingBudget: budget,
                        includeThoughts: includeThoughts,
                        thinkingLevel: thinkingLevel
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

                var safetySettings: [GoogleSafetySetting]? = nil
                if let safetyValue = dict["safetySettings"], safetyValue != .null {
                    guard case .array(let array) = safetyValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "safetySettings must be an array"
                        )
                        return .failure(error: TypeValidationError.wrap(value: safetyValue, cause: error))
                    }

                    safetySettings = try array.map { element -> GoogleSafetySetting in
                        guard case .object(let object) = element else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "each safety setting must be an object"
                            )
                            throw TypeValidationError.wrap(value: element, cause: error)
                        }

                        let categoryString = try optionalString("category", in: object) ?? ""
                        guard let category = GoogleSafetyCategory(rawValue: categoryString) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "invalid safetySettings.category value"
                            )
                            throw TypeValidationError.wrap(value: object["category"] ?? .null, cause: error)
                        }

                        let thresholdString = try optionalString("threshold", in: object) ?? ""
                        guard let threshold = GoogleSafetyThreshold(rawValue: thresholdString) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "invalid safetySettings.threshold value"
                            )
                            throw TypeValidationError.wrap(value: object["threshold"] ?? .null, cause: error)
                        }

                        return GoogleSafetySetting(
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

                var threshold: GoogleSafetyThreshold? = nil
                if let thresholdValue = dict["threshold"], thresholdValue != .null {
                    guard case .string(let thresholdRaw) = thresholdValue,
                          let parsed = GoogleSafetyThreshold(rawValue: thresholdRaw) else {
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

                var mediaResolution: GoogleMediaResolution? = nil
                if let mediaValue = dict["mediaResolution"], mediaValue != .null {
                    guard case .string(let mediaRaw) = mediaValue,
                          let parsed = GoogleMediaResolution(rawValue: mediaRaw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "mediaResolution must be a valid enum value"
                        )
                        return .failure(error: TypeValidationError.wrap(value: mediaValue, cause: error))
                    }
                    mediaResolution = parsed
                }

                var imageConfig: GoogleImageConfig? = nil
                if let imageConfigValue = dict["imageConfig"], imageConfigValue != .null {
                    guard case .object(let imageConfigDict) = imageConfigValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "imageConfig must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: imageConfigValue, cause: error))
                    }

                    try rejectNull(
                        "aspectRatio",
                        in: imageConfigDict,
                        issue: "imageConfig.aspectRatio must be a supported ratio"
                    )
                    try rejectNull(
                        "imageSize",
                        in: imageConfigDict,
                        issue: "imageConfig.imageSize must be one of '1K', '2K', '4K'"
                    )

                    var aspectRatio: GoogleImageConfigAspectRatio? = nil
                    if let aspectValue = imageConfigDict["aspectRatio"], aspectValue != .null {
                        guard case .string(let aspectRaw) = aspectValue,
                              let parsed = GoogleImageConfigAspectRatio(rawValue: aspectRaw) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "imageConfig.aspectRatio must be a supported ratio"
                            )
                            return .failure(error: TypeValidationError.wrap(value: aspectValue, cause: error))
                        }
                        aspectRatio = parsed
                    }

                    var imageSize: GoogleImageConfigImageSize? = nil
                    if let sizeValue = imageConfigDict["imageSize"], sizeValue != .null {
                        guard case .string(let sizeRaw) = sizeValue,
                              let parsed = GoogleImageConfigImageSize(rawValue: sizeRaw) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "imageConfig.imageSize must be one of '1K', '2K', '4K'"
                            )
                            return .failure(error: TypeValidationError.wrap(value: sizeValue, cause: error))
                        }
                        imageSize = parsed
                    }

                    func imageEnum(_ key: String, values: [String]) throws -> String? {
                        guard let value = imageConfigDict[key] else { return nil }
                        guard case .string(let string) = value, values.contains(string) else {
                            throw SchemaValidationIssuesError(vendor: "google", issues: "invalid imageConfig.\(key)")
                        }
                        return string
                    }
                    let person = try imageEnum("personGeneration", values: ["PERSON_GENERATION_UNSPECIFIED", "ALLOW_ALL", "ALLOW_ADULT", "ALLOW_NONE"])
                    let prominent = try imageEnum("prominentPeople", values: ["PROMINENT_PEOPLE_UNSPECIFIED", "ALLOW_PROMINENT_PEOPLE", "BLOCK_PROMINENT_PEOPLE"])
                    var output: JSONValue?
                    if let value = imageConfigDict["imageOutputOptions"] {
                        guard case .object(let object) = value else {
                            throw SchemaValidationIssuesError(vendor: "google", issues: "imageOutputOptions must be an object")
                        }
                        var fields: [String: JSONValue] = [:]
                        if let mime = object["mimeType"] {
                            guard mime == .string("image/jpeg") || mime == .string("image/png") else {
                                throw SchemaValidationIssuesError(vendor: "google", issues: "invalid imageOutputOptions.mimeType")
                            }
                            fields["mimeType"] = mime
                        }
                        if let quality = object["compressionQuality"] {
                            guard case .number = quality else { throw SchemaValidationIssuesError(vendor: "google", issues: "compressionQuality must be a number") }
                            fields["compressionQuality"] = quality
                        }
                        output = .object(fields)
                    }
                    imageConfig = GoogleImageConfig(
                        aspectRatio: aspectRatio,
                        imageSize: imageSize,
                        personGeneration: person,
                        prominentPeople: prominent,
                        imageOutputOptions: output
                    )
                }

                var retrievalConfig: GoogleRetrievalConfig? = nil
                if let retrievalValue = dict["retrievalConfig"], retrievalValue != .null {
                    guard case .object(let retrievalDict) = retrievalValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "retrievalConfig must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: retrievalValue, cause: error))
                    }

                    try rejectNull(
                        "latLng",
                        in: retrievalDict,
                        issue: "retrievalConfig.latLng must be an object"
                    )

                    var latLng: GoogleRetrievalLatLng? = nil
                    if let latLngValue = retrievalDict["latLng"], latLngValue != .null {
                        guard case .object(let latLngDict) = latLngValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "retrievalConfig.latLng must be an object"
                            )
                            return .failure(error: TypeValidationError.wrap(value: latLngValue, cause: error))
                        }

                        guard let latitudeValue = latLngDict["latitude"], case .number(let latitude) = latitudeValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "retrievalConfig.latLng.latitude must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: latLngDict["latitude"] ?? .null, cause: error))
                        }

                        guard let longitudeValue = latLngDict["longitude"], case .number(let longitude) = longitudeValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "retrievalConfig.latLng.longitude must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: latLngDict["longitude"] ?? .null, cause: error))
                        }

                        latLng = GoogleRetrievalLatLng(
                            latitude: latitude,
                            longitude: longitude
                        )
                    }

                    retrievalConfig = GoogleRetrievalConfig(latLng: latLng)
                }

                func optionEnum(_ key: String, values: [String]) throws -> String? {
                    guard let value = dict[key] else { return nil }
                    guard case .string(let string) = value, values.contains(string) else {
                        throw SchemaValidationIssuesError(vendor: "google", issues: "invalid \(key)")
                    }
                    return string
                }
                var streamArguments: Bool?
                if let value = dict["streamFunctionCallArguments"] {
                    guard case .bool(let enabled) = value else {
                        throw SchemaValidationIssuesError(vendor: "google", issues: "streamFunctionCallArguments must be a boolean")
                    }
                    streamArguments = enabled
                }
                try rejectNull("continuationToken", in: dict, issue: "continuationToken must be a string")
                let options = GoogleLanguageModelOptions(
                    responseModalities: responseModalities,
                    thinkingConfig: thinkingConfig,
                    cachedContent: cachedContent,
                    structuredOutputs: structuredOutputs,
                    safetySettings: safetySettings,
                    threshold: threshold,
                    audioTimestamp: audioTimestamp,
                    labels: labels,
                    mediaResolution: mediaResolution,
                    imageConfig: imageConfig,
                    retrievalConfig: retrievalConfig,
                    streamFunctionCallArguments: streamArguments,
                    serviceTier: try optionEnum("serviceTier", values: ["standard", "flex", "priority"]),
                    continuationToken: try optionalString("continuationToken", in: dict),
                    sharedRequestType: try optionEnum("sharedRequestType", values: ["standard", "flex", "priority"]),
                    requestType: try optionEnum("requestType", values: ["shared"])
                )

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

extension GoogleLanguageModelOptions {
    public func toDictionary() -> JSONObject {
        var result: JSONObject = [:]
        if let responseModalities { result["responseModalities"] = .array(responseModalities.map { .string($0.rawValue) }) }
        if let thinkingConfig {
            var thinking: JSONObject = [:]
            if let include = thinkingConfig.includeThoughts { thinking["includeThoughts"] = .bool(include) }
            if let budget = thinkingConfig.thinkingBudget { thinking["thinkingBudget"] = .number(budget) }
            if let level = thinkingConfig.thinkingLevel { thinking["thinkingLevel"] = .string(level.rawValue) }
            result["thinkingConfig"] = .object(thinking)
        }
        if let cachedContent { result["cachedContent"] = .string(cachedContent) }
        if let structuredOutputs { result["structuredOutputs"] = .bool(structuredOutputs) }
        if let safetySettings { result["safetySettings"] = .array(safetySettings.map { .object(["category": .string($0.category.rawValue), "threshold": .string($0.threshold.rawValue)]) }) }
        if let threshold { result["threshold"] = .string(threshold.rawValue) }
        if let audioTimestamp { result["audioTimestamp"] = .bool(audioTimestamp) }
        if let labels { result["labels"] = .object(labels.mapValues(JSONValue.string)) }
        if let mediaResolution { result["mediaResolution"] = .string(mediaResolution.rawValue) }
        if let imageConfig {
            var image: JSONObject = [:]
            if let ratio = imageConfig.aspectRatio { image["aspectRatio"] = .string(ratio.rawValue) }
            if let size = imageConfig.imageSize { image["imageSize"] = .string(size.rawValue) }
            if let person = imageConfig.personGeneration { image["personGeneration"] = .string(person) }
            if let prominent = imageConfig.prominentPeople { image["prominentPeople"] = .string(prominent) }
            if let output = imageConfig.imageOutputOptions { image["imageOutputOptions"] = output }
            result["imageConfig"] = .object(image)
        }
        if let retrievalConfig {
            var retrieval: JSONObject = [:]
            if let location = retrievalConfig.latLng { retrieval["latLng"] = .object(["latitude": .number(location.latitude), "longitude": .number(location.longitude)]) }
            result["retrievalConfig"] = .object(retrieval)
        }
        if let streamFunctionCallArguments { result["streamFunctionCallArguments"] = .bool(streamFunctionCallArguments) }
        if let serviceTier { result["serviceTier"] = .string(serviceTier) }
        if let continuationToken { result["continuationToken"] = .string(continuationToken) }
        if let sharedRequestType { result["sharedRequestType"] = .string(sharedRequestType) }
        if let requestType { result["requestType"] = .string(requestType) }
        return result
    }
}
