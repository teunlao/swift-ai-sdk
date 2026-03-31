import Foundation
import AISDKProvider

/**
 Content part types for prompts and messages.

 Port of `@ai-sdk/provider-utils/types/content-part.ts`.

 Content parts represent different types of content that can appear in messages:
 - Text content (TextPart)
 - Image content (ImagePart)
 - File content (FilePart)
 - Reasoning content (ReasoningPart)
 - Tool calls and results (ToolCallPart, ToolResultPart)
 - Tool approval requests and responses (ToolApprovalRequest, ToolApprovalResponse)
 */

// MARK: - ProviderOptions

/**
 Additional provider-specific options.

 They are passed through to the provider from the AI SDK and enable
 provider-specific functionality that can be fully encapsulated in the provider.

 Port of `@ai-sdk/provider-utils/types/provider-options.ts`.
 */
public typealias ProviderOptions = SharedV3ProviderOptions

// MARK: - Text Content

/**
 Text content part of a prompt. It contains a string of text.
 */
public struct TextPart: Sendable, Equatable, Codable {
    public let type: String = "text"

    /// The text content.
    public let text: String

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(text: String, providerOptions: ProviderOptions? = nil) {
        self.text = text
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - Image Content

/**
 Image content part of a prompt. It contains an image.
 */
public struct ImagePart: Sendable, Equatable, Codable {
    public let type: String = "image"

    /// Image data. Can either be:
    /// - data: a base64-encoded string or raw Data
    /// - URL: a URL that points to the image
    public let image: DataContentOrURL

    /// Optional IANA media type of the image.
    ///
    /// See: https://www.iana.org/assignments/media-types/media-types.xhtml
    public let mediaType: String?

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(
        image: DataContentOrURL,
        mediaType: String? = nil,
        providerOptions: ProviderOptions? = nil
    ) {
        self.image = image
        self.mediaType = mediaType
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, image, mediaType, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decode(DataContentOrURL.self, forKey: .image)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(image, forKey: .image)
        try container.encodeIfPresent(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - File Content

/**
 File content part of a prompt. It contains a file.
 */
public struct FilePart: Sendable, Equatable, Codable {
    public let type: String = "file"

    /// File data. Can either be:
    /// - data: a base64-encoded string or raw Data
    /// - URL: a URL that points to the file
    public let data: DataContentOrURL

    /// Optional filename of the file.
    public let filename: String?

    /// IANA media type of the file.
    ///
    /// See: https://www.iana.org/assignments/media-types/media-types.xhtml
    public let mediaType: String

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(
        data: DataContentOrURL,
        mediaType: String,
        filename: String? = nil,
        providerOptions: ProviderOptions? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, data, filename, mediaType, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(DataContentOrURL.self, forKey: .data)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(filename, forKey: .filename)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - Reasoning Content

/**
 Reasoning content part of a prompt. It contains reasoning text.
 */
public struct ReasoningPart: Sendable, Equatable, Codable {
    public let type: String = "reasoning"

    /// The reasoning text.
    public let text: String

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(text: String, providerOptions: ProviderOptions? = nil) {
        self.text = text
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - Tool Call

/**
 Tool call content part of a prompt. It contains a tool call (usually generated by the AI model).
 */
public struct ToolCallPart: Sendable, Equatable, Codable {
    public let type: String = "tool-call"

    /// ID of the tool call. This ID is used to match the tool call with the tool result.
    public let toolCallId: String

    /// Name of the tool that is being called.
    public let toolName: String

    /// Arguments of the tool call. This is a JSON-serializable object that matches the tool's input schema.
    public let input: JSONValue

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    /// Whether the tool call was executed by the provider.
    public let providerExecuted: Bool?

    public init(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerOptions: ProviderOptions? = nil,
        providerExecuted: Bool? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerOptions = providerOptions
        self.providerExecuted = providerExecuted
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolCallId, toolName, input, providerOptions, providerExecuted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        input = try container.decode(JSONValue.self, forKey: .input)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
        providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)
    }
}

// MARK: - Tool Result

/**
 Tool result content part of a prompt. It contains the result of the tool call with the matching ID.
 */
public struct ToolResultPart: Sendable, Equatable, Codable {
    public let type: String = "tool-result"

    /// ID of the tool call that this result is associated with.
    public let toolCallId: String

    /// Name of the tool that generated this result.
    public let toolName: String

    /// Result of the tool call. This is a JSON-serializable object.
    public let output: LanguageModelV3ToolResultOutput

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(
        toolCallId: String,
        toolName: String,
        output: LanguageModelV3ToolResultOutput,
        providerOptions: ProviderOptions? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.output = output
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolCallId, toolName, output, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        output = try container.decode(LanguageModelV3ToolResultOutput.self, forKey: .output)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - Tool Approval

/**
 Tool approval request prompt part.

 Port of `@ai-sdk/provider-utils/types/tool-approval-request.ts`.
 */
public struct ToolApprovalRequest: Sendable, Equatable, Codable {
    public let type: String = "tool-approval-request"

    /// ID of the tool approval.
    public let approvalId: String

    /// ID of the tool call that the approval request is for.
    public let toolCallId: String

    public init(approvalId: String, toolCallId: String) {
        self.approvalId = approvalId
        self.toolCallId = toolCallId
    }

    private enum CodingKeys: String, CodingKey {
        case type, approvalId, toolCallId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        approvalId = try container.decode(String.self, forKey: .approvalId)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(approvalId, forKey: .approvalId)
        try container.encode(toolCallId, forKey: .toolCallId)
    }
}

/**
 Tool approval response prompt part.

 Port of `@ai-sdk/provider-utils/types/tool-approval-response.ts`.
 */
public struct ToolApprovalResponse: Sendable, Equatable, Codable {
    public let type: String = "tool-approval-response"

    /// ID of the tool approval.
    public let approvalId: String

    /// Flag indicating whether the approval was granted or denied.
    public let approved: Bool

    /// Optional reason for the approval or denial.
    public let reason: String?

    /// Flag indicating whether the tool call is provider-executed.
    /// Only provider-executed tool approval responses should be sent to the model.
    public let providerExecuted: Bool?

    public init(approvalId: String, approved: Bool, reason: String? = nil, providerExecuted: Bool? = nil) {
        self.approvalId = approvalId
        self.approved = approved
        self.reason = reason
        self.providerExecuted = providerExecuted
    }

    private enum CodingKeys: String, CodingKey {
        case type, approvalId, approved, reason, providerExecuted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        approvalId = try container.decode(String.self, forKey: .approvalId)
        approved = try container.decode(Bool.self, forKey: .approved)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(approvalId, forKey: .approvalId)
        try container.encode(approved, forKey: .approved)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)
    }
}

// MARK: - UserContentPart

/**
 Content part types allowed in user messages.
 */
public enum UserContentPart: Sendable, Equatable, Codable {
    case text(TextPart)
    case image(ImagePart)
    case file(FilePart)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextPart(from: decoder))
        case "image":
            self = .image(try ImagePart(from: decoder))
        case "file":
            self = .file(try FilePart(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown UserContentPart type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let part):
            try part.encode(to: encoder)
        case .image(let part):
            try part.encode(to: encoder)
        case .file(let part):
            try part.encode(to: encoder)
        }
    }
}

// MARK: - AssistantContentPart

/**
 Content part types allowed in assistant messages.
 */
public enum AssistantContentPart: Sendable, Equatable, Codable {
    case text(TextPart)
    case file(FilePart)
    case reasoning(ReasoningPart)
    case toolCall(ToolCallPart)
    case toolResult(ToolResultPart)
    case toolApprovalRequest(ToolApprovalRequest)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextPart(from: decoder))
        case "file":
            self = .file(try FilePart(from: decoder))
        case "reasoning":
            self = .reasoning(try ReasoningPart(from: decoder))
        case "tool-call":
            self = .toolCall(try ToolCallPart(from: decoder))
        case "tool-result":
            self = .toolResult(try ToolResultPart(from: decoder))
        case "tool-approval-request":
            self = .toolApprovalRequest(try ToolApprovalRequest(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown AssistantContentPart type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let part):
            try part.encode(to: encoder)
        case .file(let part):
            try part.encode(to: encoder)
        case .reasoning(let part):
            try part.encode(to: encoder)
        case .toolCall(let part):
            try part.encode(to: encoder)
        case .toolResult(let part):
            try part.encode(to: encoder)
        case .toolApprovalRequest(let part):
            try part.encode(to: encoder)
        }
    }
}

// MARK: - ToolContentPart

/**
 Content part types allowed in tool messages.
 */
public enum ToolContentPart: Sendable, Equatable, Codable {
    case toolResult(ToolResultPart)
    case toolApprovalResponse(ToolApprovalResponse)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "tool-result":
            self = .toolResult(try ToolResultPart(from: decoder))
        case "tool-approval-response":
            self = .toolApprovalResponse(try ToolApprovalResponse(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ToolContentPart type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .toolResult(let part):
            try part.encode(to: encoder)
        case .toolApprovalResponse(let part):
            try part.encode(to: encoder)
        }
    }
}

// MARK: - UserContent

/**
 Content of a user message. It can be a string or an array of text, image, and file parts.
 */
public enum UserContent: Sendable, Equatable, Codable {
    /// Simple text content
    case text(String)
    /// Array of content parts (text, images, files)
    case parts([UserContentPart])

    private enum CodingKeys: String, CodingKey {
        case type, value, parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case "parts":
            let parts = try container.decode([UserContentPart].self, forKey: .parts)
            self = .parts(parts)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown UserContent type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .parts(let parts):
            try container.encode("parts", forKey: .type)
            try container.encode(parts, forKey: .parts)
        }
    }
}

// MARK: - AssistantContent

/**
 Content of an assistant message.
 It can be a string or an array of text, file, reasoning, tool call, tool result, and approval request parts.
 */
public enum AssistantContent: Sendable, Equatable, Codable {
    /// Simple text content
    case text(String)
    /// Array of content parts
    case parts([AssistantContentPart])

    private enum CodingKeys: String, CodingKey {
        case type, value, parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case "parts":
            let parts = try container.decode([AssistantContentPart].self, forKey: .parts)
            self = .parts(parts)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown AssistantContent type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .parts(let parts):
            try container.encode("parts", forKey: .type)
            try container.encode(parts, forKey: .parts)
        }
    }
}
