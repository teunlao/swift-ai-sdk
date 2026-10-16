import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleInteractionsModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}
public enum GoogleInteractionsAgentName: String, Sendable {
    case deepResearchPro = "deep-research-pro-preview-12-2025"
    case deepResearch = "deep-research-preview-04-2026"
    case deepResearchMax = "deep-research-max-preview-04-2026"
    case antigravity = "antigravity-preview-05-2026"
}
public enum GoogleInteractionsModelInput: Sendable {
    case model(String)
    case agent(GoogleInteractionsAgentName)
    case managedAgent(String)
}
public struct GoogleInteractionsVideoOptions: Sendable, Equatable {
    public enum Processing: Sendable, Equatable {
        case agentic
        case `static`(startOffset: Double? = nil, endOffset: Double? = nil, fps: Double? = nil)
    }
    public var processing: Processing?
    public init(processing: Processing? = nil) { self.processing = processing }
}

public struct GoogleLanguageModelInteractionsOptions: Sendable, Codable, Equatable {
    public var previousInteractionId: String?
    public var store: Bool?
    public var agent: String?
    public var agentConfig: JSONObject?
    public var thinkingLevel: String?
    public var thinkingSummaries: String?
    public var responseFormat: [JSONObject]?
    public var imageConfig: JSONObject?
    public var mediaResolution: String?
    public var responseModalities: [String]?
    public var serviceTier: String?
    public var systemInstruction: String?
    public var signature: String?
    public var interactionId: String?
    public var pollingTimeoutMs: Int?
    public var background: Bool?
    public var environment: JSONValue?
    public init(previousInteractionId: String? = nil, store: Bool? = nil, agent: String? = nil, agentConfig: JSONObject? = nil, thinkingLevel: String? = nil, thinkingSummaries: String? = nil, responseFormat: [JSONObject]? = nil, imageConfig: JSONObject? = nil, mediaResolution: String? = nil, responseModalities: [String]? = nil, serviceTier: String? = nil, systemInstruction: String? = nil, signature: String? = nil, interactionId: String? = nil, pollingTimeoutMs: Int? = nil, background: Bool? = nil, environment: JSONValue? = nil) {
        self.previousInteractionId = previousInteractionId; self.store = store; self.agent = agent; self.agentConfig = agentConfig
        self.thinkingLevel = thinkingLevel; self.thinkingSummaries = thinkingSummaries; self.responseFormat = responseFormat; self.imageConfig = imageConfig
        self.mediaResolution = mediaResolution; self.responseModalities = responseModalities; self.serviceTier = serviceTier; self.systemInstruction = systemInstruction
        self.signature = signature; self.interactionId = interactionId; self.pollingTimeoutMs = pollingTimeoutMs; self.background = background; self.environment = environment
    }
}

let googleInteractionsOptionsSchema = FlexibleSchema(Schema<GoogleLanguageModelInteractionsOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let options = try JSONDecoder().decode(GoogleLanguageModelInteractionsOptions.self, from: JSONEncoder().encode(jsonValue(from: value)))
        func check(_ value: String?, _ allowed: [String], _ key: String) throws {
            if let value, !allowed.contains(value) { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid \(key)") }
        }
        try check(options.thinkingLevel, ["minimal", "low", "medium", "high"], "thinkingLevel")
        try check(options.thinkingSummaries, ["auto", "none"], "thinkingSummaries")
        try check(options.mediaResolution, ["low", "medium", "high", "ultra_high"], "mediaResolution")
        try check(options.serviceTier, ["flex", "standard", "priority"], "serviceTier")
        for modality in options.responseModalities ?? [] { try check(modality, ["text", "image", "audio", "video", "document"], "responseModalities") }
        if let timeout = options.pollingTimeoutMs, timeout <= 0 { throw SchemaValidationIssuesError(vendor: "google", issues: "pollingTimeoutMs must be positive") }
        func string(_ object: JSONObject, _ key: String) throws -> String? {
            guard let value = object[key], value != .null else { return nil }
            guard case .string(let result) = value else { throw SchemaValidationIssuesError(vendor: "google", issues: "\(key) must be a string") }
            return result
        }
        func image(_ object: JSONObject) throws {
            try check(try string(object, "aspectRatio"), ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9", "1:8", "8:1", "1:4", "4:1"], "aspectRatio")
            try check(try string(object, "imageSize"), ["1K", "2K", "4K", "512"], "imageSize")
        }
        if let config = options.imageConfig { try image(config) }
        for entry in options.responseFormat ?? [] {
            guard let type = try string(entry, "type"), ["text", "image", "audio", "video"].contains(type) else { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid responseFormat type") }
            _ = try string(entry, "mimeType")
            if type == "image" { try image(entry) }
            if type == "video" {
                try check(try string(entry, "aspectRatio"), ["16:9", "9:16"], "aspectRatio")
                try check(try string(entry, "resolution"), ["360p", "720p", "1080p", "4k"], "resolution")
                try check(try string(entry, "delivery"), ["inline", "uri"], "delivery")
                _ = try string(entry, "duration"); _ = try string(entry, "gcsUri")
            }
        }
        if let agent = options.agentConfig {
            guard let type = try string(agent, "type"), ["dynamic", "deep-research"].contains(type) else { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid agentConfig type") }
            if type == "deep-research" {
                try check(try string(agent, "thinkingSummaries"), ["auto", "none"], "thinkingSummaries")
                try check(try string(agent, "visualization"), ["off", "auto"], "visualization")
                if let value = agent["collaborativePlanning"], value != .null, case .bool = value {} else if let value = agent["collaborativePlanning"], value != .null { throw SchemaValidationIssuesError(vendor: "google", issues: "collaborativePlanning must be a boolean") }
            }
        }
        if let environment = options.environment, environment != .null {
            if case .string = environment {} else {
                guard case .object(let object) = environment, object["type"] == .string("remote") else { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid environment") }
                if let value = object["sources"], value != .null {
                    guard case .array(let sources) = value else { throw SchemaValidationIssuesError(vendor: "google", issues: "sources must be an array") }
                    for source in sources {
                        guard case .object(let fields) = source, let type = try string(fields, "type"), ["gcs", "repository", "inline"].contains(type) else { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid environment source") }
                        guard try string(fields, type == "inline" ? "content" : "source") != nil else { throw SchemaValidationIssuesError(vendor: "google", issues: "source content required") }
                        let target = try string(fields, "target")
                        if type == "inline", target == nil { throw SchemaValidationIssuesError(vendor: "google", issues: "inline source target required") }
                    }
                }
                if let network = object["network"], network != .null, network != .string("disabled") {
                    guard case .object(let network) = network, case .array(let entries) = network["allowlist"] else { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid network") }
                    for entry in entries {
                        guard case .object(let fields) = entry, try string(fields, "domain") != nil else { throw SchemaValidationIssuesError(vendor: "google", issues: "allowlist domain required") }
                        if let transform = fields["transform"], transform != .null {
                            guard case .array(let transforms) = transform else { throw SchemaValidationIssuesError(vendor: "google", issues: "transform must be an array") }
                            for value in transforms {
                                guard case .object(let fields) = value, fields.values.allSatisfy({ if case .string = $0 { return true }; return false }) else { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid transform") }
                            }
                        }
                    }
                }
            }
        }
        return .success(value: options)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))
