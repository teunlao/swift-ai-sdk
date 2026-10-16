import Foundation
import AISDKProvider

public struct GooglePrompt: Sendable, Equatable {
    public var systemInstruction: GoogleSystemInstruction?
    public var contents: [GoogleContent]

    public init(systemInstruction: GoogleSystemInstruction? = nil, contents: [GoogleContent]) {
        self.systemInstruction = systemInstruction
        self.contents = contents
    }
}

public struct GoogleSystemInstruction: Sendable, Equatable {
    public var parts: [GoogleSystemInstructionPart]

    public init(parts: [GoogleSystemInstructionPart]) {
        self.parts = parts
    }
}

public struct GoogleSystemInstructionPart: Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct GoogleContent: Sendable, Equatable {
    public enum Role: String, Sendable, Equatable {
        case user
        case model
    }

    public var role: Role
    public var parts: [GoogleContentPart]

    public init(role: Role, parts: [GoogleContentPart]) {
        self.role = role
        self.parts = parts
    }
}

public enum GoogleContentPart: Sendable, Equatable {
    case text(GoogleTextPart)
    case inlineData(GoogleInlineDataPart)
    case functionCall(GoogleFunctionCallPart)
    case functionResponse(GoogleFunctionResponse)
    case fileData(GoogleFileDataPart)
    case raw(JSONValue)
}

public struct GoogleTextPart: Sendable, Equatable {
    public var text: String
    public var thought: Bool?
    public var thoughtSignature: String?

    public init(text: String, thought: Bool? = nil, thoughtSignature: String? = nil) {
        self.text = text
        self.thought = thought
        self.thoughtSignature = thoughtSignature
    }
}

public struct GoogleInlineDataPart: Sendable, Equatable {
    public var mimeType: String
    public var data: String
    public var thoughtSignature: String?
    public var thought: Bool?

    public init(mimeType: String, data: String, thoughtSignature: String? = nil, thought: Bool? = nil) {
        self.mimeType = mimeType
        self.data = data
        self.thoughtSignature = thoughtSignature
        self.thought = thought
    }
}

public struct GoogleFunctionCallPart: Sendable, Equatable {
    public var id: String?
    public var name: String
    public var arguments: JSONValue
    public var thoughtSignature: String?

    public init(id: String? = nil, name: String, arguments: JSONValue, thoughtSignature: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.thoughtSignature = thoughtSignature
    }
}

public struct GoogleFunctionResponsePart: Sendable, Equatable {
    public var inlineData: GoogleInlineDataPart

    public init(inlineData: GoogleInlineDataPart) {
        self.inlineData = inlineData
    }

    public init(mimeType: String, data: String, thoughtSignature: String? = nil) {
        self.inlineData = GoogleInlineDataPart(mimeType: mimeType, data: data, thoughtSignature: thoughtSignature)
    }
}

public struct GoogleFunctionResponse: Sendable, Equatable {
    public var id: String?
    public var name: String
    public var response: JSONValue
    public var parts: [GoogleFunctionResponsePart]?

    public init(
        id: String? = nil,
        name: String,
        response: JSONValue,
        parts: [GoogleFunctionResponsePart]? = nil
    ) {
        self.id = id
        self.name = name
        self.response = response
        self.parts = parts
    }
}

public struct GoogleFileDataPart: Sendable, Equatable {
    public var mimeType: String
    public var fileURI: String

    public init(mimeType: String, fileURI: String) {
        self.mimeType = mimeType
        self.fileURI = fileURI
    }
}

public struct GoogleProviderMetadata: Sendable, Equatable, Codable {
    public var promptFeedback: GooglePromptFeedback?
    public var groundingMetadata: GoogleGroundingMetadata?
    public var urlContextMetadata: GoogleUrlContextMetadata?
    public var safetyRatings: [GoogleSafetyRating]?
    public var usageMetadata: GoogleUsageMetadata?
    public var finishReason: String?
    public var finishMessage: String?
    public var serviceTier: String?
    public var continuationToken: String?
    public var initialPromptTokenCount: Int?

    public init(promptFeedback: GooglePromptFeedback? = nil, groundingMetadata: GoogleGroundingMetadata? = nil, urlContextMetadata: GoogleUrlContextMetadata? = nil, safetyRatings: [GoogleSafetyRating]? = nil, usageMetadata: GoogleUsageMetadata? = nil, finishReason: String? = nil, finishMessage: String? = nil, serviceTier: String? = nil, continuationToken: String? = nil, initialPromptTokenCount: Int? = nil) {
        self.promptFeedback = promptFeedback; self.groundingMetadata = groundingMetadata; self.urlContextMetadata = urlContextMetadata; self.safetyRatings = safetyRatings
        self.usageMetadata = usageMetadata; self.finishReason = finishReason; self.finishMessage = finishMessage; self.serviceTier = serviceTier
        self.continuationToken = continuationToken; self.initialPromptTokenCount = initialPromptTokenCount
    }
}

public typealias GoogleGroundingMetadata = GroundingMetadataSchema
public typealias GoogleUrlContextMetadata = UrlContextMetadataSchema
public typealias GoogleSafetyRating = SafetyRatingSchema
public typealias GooglePromptFeedback = JSONValue
public typealias GoogleUsageMetadata = JSONValue
