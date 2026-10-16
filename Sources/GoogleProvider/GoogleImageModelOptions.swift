import AISDKProvider

public enum GooglePersonGeneration: String, Sendable, Equatable, Codable {
    case dontAllow = "dont_allow"
    case allowAdult = "allow_adult"
    case allowAll = "allow_all"
}

public struct GoogleImageModelOptions: Sendable, Equatable {
    public var googleSearch: GoogleSearchArgs?
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
    public init(googleSearch: GoogleSearchArgs? = nil, thinkingConfig: GoogleThinkingConfig? = nil, cachedContent: String? = nil, structuredOutputs: Bool? = nil, safetySettings: [GoogleSafetySetting]? = nil, threshold: GoogleSafetyThreshold? = nil, audioTimestamp: Bool? = nil, labels: [String: String]? = nil, mediaResolution: GoogleMediaResolution? = nil, imageConfig: GoogleImageConfig? = nil, retrievalConfig: GoogleRetrievalConfig? = nil, streamFunctionCallArguments: Bool? = nil, serviceTier: String? = nil, continuationToken: String? = nil, sharedRequestType: String? = nil, requestType: String? = nil) {
        self.googleSearch = googleSearch; self.thinkingConfig = thinkingConfig; self.cachedContent = cachedContent; self.structuredOutputs = structuredOutputs
        self.safetySettings = safetySettings; self.threshold = threshold; self.audioTimestamp = audioTimestamp; self.labels = labels
        self.mediaResolution = mediaResolution; self.imageConfig = imageConfig; self.retrievalConfig = retrievalConfig
        self.streamFunctionCallArguments = streamFunctionCallArguments; self.serviceTier = serviceTier; self.continuationToken = continuationToken; self.sharedRequestType = sharedRequestType; self.requestType = requestType
    }
    public func toDictionary() -> JSONObject {
        var result = GoogleLanguageModelOptions(thinkingConfig: thinkingConfig, cachedContent: cachedContent, structuredOutputs: structuredOutputs, safetySettings: safetySettings, threshold: threshold, audioTimestamp: audioTimestamp, labels: labels, mediaResolution: mediaResolution, imageConfig: imageConfig, retrievalConfig: retrievalConfig, streamFunctionCallArguments: streamFunctionCallArguments, serviceTier: serviceTier, continuationToken: continuationToken, sharedRequestType: sharedRequestType, requestType: requestType).toDictionary()
        if let googleSearch { result["googleSearch"] = .object(googleSearch.toDictionary()) }
        return result
    }
}
