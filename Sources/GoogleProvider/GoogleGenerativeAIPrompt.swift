import Foundation
import AISDKProvider

public struct GoogleGenerativeAIPrompt: Sendable, Equatable {
    public var systemInstruction: GoogleGenerativeAISystemInstruction?
    public var contents: [GoogleGenerativeAIContent]

    public init(systemInstruction: GoogleGenerativeAISystemInstruction? = nil, contents: [GoogleGenerativeAIContent]) {
        self.systemInstruction = systemInstruction
        self.contents = contents
    }
}

public struct GoogleGenerativeAISystemInstruction: Sendable, Equatable {
    public var parts: [GoogleGenerativeAISystemInstructionPart]

    public init(parts: [GoogleGenerativeAISystemInstructionPart]) {
        self.parts = parts
    }
}

public struct GoogleGenerativeAISystemInstructionPart: Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct GoogleGenerativeAIContent: Sendable, Equatable {
    public enum Role: String, Sendable, Equatable {
        case user
        case model
    }

    public var role: Role
    public var parts: [GoogleGenerativeAIContentPart]

    public init(role: Role, parts: [GoogleGenerativeAIContentPart]) {
        self.role = role
        self.parts = parts
    }
}

public enum GoogleGenerativeAIContentPart: Sendable, Equatable {
    case text(GoogleGenerativeAITextPart)
    case inlineData(GoogleGenerativeAIInlineDataPart)
    case functionCall(GoogleGenerativeAIFunctionCallPart)
    case functionResponse(GoogleGenerativeAIFunctionResponsePart)
    case fileData(GoogleGenerativeAIFileDataPart)
}

public struct GoogleGenerativeAITextPart: Sendable, Equatable {
    public var text: String
    public var thought: Bool?
    public var thoughtSignature: String?

    public init(text: String, thought: Bool? = nil, thoughtSignature: String? = nil) {
        self.text = text
        self.thought = thought
        self.thoughtSignature = thoughtSignature
    }
}

public struct GoogleGenerativeAIInlineDataPart: Sendable, Equatable {
    public var mimeType: String
    public var data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

public struct GoogleGenerativeAIFunctionCallPart: Sendable, Equatable {
    public var name: String
    public var arguments: JSONValue
    public var thoughtSignature: String?

    public init(name: String, arguments: JSONValue, thoughtSignature: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.thoughtSignature = thoughtSignature
    }
}

public struct GoogleGenerativeAIFunctionResponsePart: Sendable, Equatable {
    public var name: String
    public var response: JSONValue

    public init(name: String, response: JSONValue) {
        self.name = name
        self.response = response
    }
}

public struct GoogleGenerativeAIFileDataPart: Sendable, Equatable {
    public var mimeType: String
    public var fileURI: String

    public init(mimeType: String, fileURI: String) {
        self.mimeType = mimeType
        self.fileURI = fileURI
    }
}

public struct GoogleGenerativeAIProviderMetadata: Sendable, Equatable {
    public var groundingMetadata: GoogleGenerativeAIGroundingMetadata?
    public var urlContextMetadata: GoogleGenerativeAIUrlContextMetadata?
    public var safetyRatings: [GoogleGenerativeAISafetyRating]?

    public init(
        groundingMetadata: GoogleGenerativeAIGroundingMetadata? = nil,
        urlContextMetadata: GoogleGenerativeAIUrlContextMetadata? = nil,
        safetyRatings: [GoogleGenerativeAISafetyRating]? = nil
    ) {
        self.groundingMetadata = groundingMetadata
        self.urlContextMetadata = urlContextMetadata
        self.safetyRatings = safetyRatings
    }
}

public typealias GoogleGenerativeAIGroundingMetadata = GroundingMetadataSchema
public typealias GoogleGenerativeAIUrlContextMetadata = UrlContextMetadataSchema
public typealias GoogleGenerativeAISafetyRating = SafetyRatingSchema
