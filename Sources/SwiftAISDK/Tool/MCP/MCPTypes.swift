/**
 Model Context Protocol (MCP) type definitions.

 Port of `packages/mcp/src/tool/types.ts`.
 Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4

 This module defines the core types for the Model Context Protocol, including
 protocol versioning, tool schemas, server capabilities, and result types.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Protocol Versioning

/// Latest supported legacy MCP protocol version
public let latestProtocolVersion = "2025-11-25"

/// All supported legacy MCP protocol versions (newest to oldest)
public let supportedProtocolVersions = [
    latestProtocolVersion,
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
]

/// Alias matching upstream naming (`LATEST_PROTOCOL_VERSION`).
public let LATEST_PROTOCOL_VERSION = latestProtocolVersion

/// Alias matching upstream naming (`SUPPORTED_PROTOCOL_VERSIONS`).
public let SUPPORTED_PROTOCOL_VERSIONS = supportedProtocolVersions

// MARK: - Tool Schemas

/// MCP tool metadata - keys should follow MCP `_meta` key format specification.
public typealias ToolMeta = [String: JSONValue]

/// Tool schema definitions for MCP tools.
/// Can be explicit schemas or "automatic" for dynamic discovery.
public enum ToolSchemas: Sendable {
    case automatic
    case schemas([String: ToolSchemaDefinition])
}

/// Definition of a tool schema (user-facing API)
public struct ToolSchemaDefinition: Sendable {
    public let inputSchema: FlexibleSchema<JSONValue>
    public let outputSchema: FlexibleSchema<JSONValue>?

    public init(
        inputSchema: FlexibleSchema<JSONValue>,
        outputSchema: FlexibleSchema<JSONValue>? = nil
    ) {
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
    }
}

// MARK: - Base Types

/// Client or server implementation metadata
public struct Configuration: Codable, Sendable {
    public let name: String
    public let version: String
    public let title: String?

    public init(name: String, version: String, title: String? = nil) {
        self.name = name
        self.version = version
        self.title = title
    }
}

/// Base parameters structure (can include optional _meta field)
public struct BaseParams: Codable, Sendable {
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: [String: JSONValue]? = nil) {
        self.meta = meta
    }
}

/// MCP request structure
public struct Request: Codable, Sendable {
    public let method: String
    public let params: BaseParams?

    public init(method: String, params: BaseParams? = nil) {
        self.method = method
        self.params = params
    }
}

/// Request options for controlling request behavior
public struct RequestOptions: Sendable {
    /// Cancellation check function
    public let signal: (@Sendable () -> Bool)?
    /// Timeout for this specific request
    public let timeout: TimeInterval?
    /// Maximum total request timeout in seconds
    public let maxTotalTimeout: TimeInterval?

    public init(
        signal: (@Sendable () -> Bool)? = nil,
        timeout: TimeInterval? = nil,
        maxTotalTimeout: TimeInterval? = nil
    ) {
        self.signal = signal
        self.timeout = timeout
        self.maxTotalTimeout = maxTotalTimeout
    }
}

/// MCP notification (same structure as request, but no response expected)
public typealias Notification = Request

// MARK: - Server Capabilities

/// @see https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation
public struct ElicitationCapability: Codable, Sendable {
    public let applyDefaults: Bool?

    public init(applyDefaults: Bool? = nil) {
        self.applyDefaults = applyDefaults
    }
}

/// Server capabilities describing what the MCP server supports
public struct ServerCapabilities: Codable, Sendable {
    public let experimental: [String: JSONValue]?
    public let logging: [String: JSONValue]?
    public let completions: [String: JSONValue]?
    public let prompts: PromptsCapabilities?
    public let resources: ResourcesCapabilities?
    public let tools: ToolsCapabilities?
    public let elicitation: ElicitationCapability?

    public init(
        experimental: [String: JSONValue]? = nil,
        logging: [String: JSONValue]? = nil,
        completions: [String: JSONValue]? = nil,
        prompts: PromptsCapabilities? = nil,
        resources: ResourcesCapabilities? = nil,
        tools: ToolsCapabilities? = nil,
        elicitation: ElicitationCapability? = nil
    ) {
        self.experimental = experimental
        self.logging = logging
        self.completions = completions
        self.prompts = prompts
        self.resources = resources
        self.tools = tools
        self.elicitation = elicitation
    }

    public struct PromptsCapabilities: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public struct ResourcesCapabilities: Codable, Sendable {
        public let subscribe: Bool?
        public let listChanged: Bool?

        public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
            self.subscribe = subscribe
            self.listChanged = listChanged
        }
    }

    public struct ToolsCapabilities: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }
}

/// Client capabilities advertised during initialization.
public struct ClientCapabilities: Codable, Sendable {
    public let elicitation: ElicitationCapability?
    public let extensions: [String: JSONValue]?

    public init(elicitation: ElicitationCapability? = nil, extensions: [String: JSONValue]? = nil) {
        self.elicitation = elicitation
        self.extensions = extensions
    }
}

/// Result of MCP initialization
public struct InitializeResult: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: ServerCapabilities
    public let serverInfo: Configuration
    public let instructions: String?
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case capabilities
        case serverInfo
        case instructions
        case meta = "_meta"
    }

    public init(
        protocolVersion: String,
        capabilities: ServerCapabilities,
        serverInfo: Configuration,
        instructions: String? = nil,
        meta: [String: JSONValue]? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
        self.instructions = instructions
        self.meta = meta
    }
}

// MARK: - Paginated Requests

/// Request that supports pagination
public struct PaginatedRequest: Codable, Sendable {
    public let method: String
    public let params: PaginatedParams?

    public init(method: String, params: PaginatedParams? = nil) {
        self.method = method
        self.params = params
    }

    public struct PaginatedParams: Codable, Sendable {
        public let cursor: String?
        public let meta: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case cursor
            case meta = "_meta"
        }

        public init(cursor: String? = nil, meta: [String: JSONValue]? = nil) {
            self.cursor = cursor
            self.meta = meta
        }
    }
}

/// Result that supports pagination
public struct PaginatedResult: Codable, Sendable {
    public let nextCursor: String?
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case nextCursor
        case meta = "_meta"
    }

    public init(nextCursor: String? = nil, meta: [String: JSONValue]? = nil) {
        self.nextCursor = nextCursor
        self.meta = meta
    }
}

// MARK: - Tool Types

/// Tool annotations (loose object in the wire protocol).
public struct MCPToolAnnotations: Codable, Sendable {
    public let title: String?
    public let readOnlyHint: Bool?
    public let destructiveHint: Bool?
    public let idempotentHint: Bool?
    public let openWorldHint: Bool?

    public init(
        title: String? = nil,
        readOnlyHint: Bool? = nil,
        destructiveHint: Bool? = nil,
        idempotentHint: Bool? = nil,
        openWorldHint: Bool? = nil
    ) {
        self.title = title
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
    }
}

public struct McpProviderMetadata: Codable, Sendable {
    public let clientName: String?
    public let title: String?
    public let toolName: String?
    public let annotations: MCPToolAnnotations?
    public let app: [String: JSONValue]?

    public init(clientName: String? = nil, title: String? = nil, toolName: String? = nil, annotations: MCPToolAnnotations? = nil, app: [String: JSONValue]? = nil) {
        self.clientName = clientName
        self.title = title
        self.toolName = toolName
        self.annotations = annotations
        self.app = app
    }
}

/// MCP tool definition (from wire protocol)
public struct MCPTool: Codable, Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue?
    public let annotations: MCPToolAnnotations?
    public let meta: ToolMeta?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case inputSchema
        case outputSchema
        case annotations
        case meta = "_meta"
    }

    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue,
        outputSchema: JSONValue? = nil,
        annotations: MCPToolAnnotations? = nil,
        meta: ToolMeta? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        self.meta = meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        inputSchema = try container.decode(JSONValue.self, forKey: .inputSchema)
        guard case .object(let input) = inputSchema else {
            throw DecodingError.dataCorruptedError(forKey: .inputSchema, in: container, debugDescription: "Tool inputSchema must be an object")
        }
        if let properties = input["properties"], case .object = properties {} else if input["properties"] != nil {
            throw DecodingError.dataCorruptedError(forKey: .inputSchema, in: container, debugDescription: "Tool properties must be an object")
        }
        outputSchema = try container.decodeIfPresent(JSONValue.self, forKey: .outputSchema)
        if let outputSchema, case .object = outputSchema {} else if outputSchema != nil {
            throw DecodingError.dataCorruptedError(forKey: .outputSchema, in: container, debugDescription: "Tool outputSchema must be an object")
        }
        annotations = try container.decodeIfPresent(MCPToolAnnotations.self, forKey: .annotations)
        meta = try container.decodeIfPresent(ToolMeta.self, forKey: .meta)
    }
}

/// Result of listing available tools
public struct ListToolsResult: Codable, Sendable {
    public let tools: [MCPTool]
    public let nextCursor: String?
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case tools
        case nextCursor
        case meta = "_meta"
    }

    public init(
        tools: [MCPTool],
        nextCursor: String? = nil,
        meta: [String: JSONValue]? = nil
    ) {
        self.tools = tools
        self.nextCursor = nextCursor
        self.meta = meta
    }
}

// MARK: - Resource Types

/// Resource definition (from wire protocol).
public struct MCPResource: Codable, Sendable {
    public let uri: String
    public let name: String
    public let title: String?
    public let description: String?
    public let mimeType: String?
    public let size: Double?

    public init(
        uri: String,
        name: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        size: Double? = nil
    ) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
        self.size = size
    }
}

/// Result of listing available resources.
public struct ListResourcesResult: Codable, Sendable {
    public let resources: [MCPResource]
    public let nextCursor: String?
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case resources
        case nextCursor
        case meta = "_meta"
    }

    public init(
        resources: [MCPResource],
        nextCursor: String? = nil,
        meta: [String: JSONValue]? = nil
    ) {
        self.resources = resources
        self.nextCursor = nextCursor
        self.meta = meta
    }
}

// MARK: - Content Types

/// Content types that can be returned from tool calls
public enum ToolContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResource)
    case unknown(JSONValue)

    public struct TextContent: Codable, Sendable {
        public let type: String = "text"
        public let text: String

        public init(text: String) {
            self.text = text
        }
    }

    public struct ImageContent: Codable, Sendable {
        public let type: String = "image"
        public let data: String // base64
        public let mimeType: String

        public init(data: String, mimeType: String) {
            self.data = data
            self.mimeType = mimeType
        }
    }

    public struct EmbeddedResource: Codable, Sendable {
        public let type: String = "resource"
        public let resource: ResourceContents

        public init(resource: ResourceContents) {
            self.resource = resource
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextContent(from: decoder))
        case "image":
            let image = try ImageContent(from: decoder)
            guard Data(base64Encoded: image.data) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid base64 image")
            }
            self = .image(image)
        case "resource":
            self = .resource(try EmbeddedResource(from: decoder))
        case "resource_link":
            let value = try JSONValue(from: decoder)
            guard case .object(let object) = value,
                  case .string = object["uri"], case .string = object["name"] else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Resource link requires uri and name")
            }
            for key in ["description", "mimeType"] {
                if let value = object[key], case .string = value {} else if object[key] != nil {
                    throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid resource link field")
                }
            }
            self = .unknown(value)
        default:
            // Upstream parses content parts loosely and keeps unknown shapes. Preserve the raw JSON
            // so callers can still access and forward it (e.g. via toModelOutput fallback).
            self = .unknown(try JSONValue(from: decoder))
        }
        if case .object(let raw) = try JSONValue(from: decoder) {
            let knownKeys: Set<String>
            switch type {
            case "text": knownKeys = ["type", "text"]
            case "image": knownKeys = ["type", "data", "mimeType"]
            case "resource": knownKeys = ["type", "resource"]
            default: return
            }
            if !Set(raw.keys).isSubset(of: knownKeys) { self = .unknown(.object(raw)) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        case .unknown(let value):
            try value.encode(to: encoder)
        }
    }
}

/// Resource contents (text or blob)
public enum ResourceContents: Codable, Sendable {
    case text(uri: String, name: String?, title: String?, mimeType: String?, text: String, meta: JSONValue? = nil, additionalProperties: [String: JSONValue] = [:])
    case blob(uri: String, name: String?, title: String?, mimeType: String?, blob: String, meta: JSONValue? = nil, additionalProperties: [String: JSONValue] = [:]) // base64

    enum CodingKeys: String, CodingKey {
        case uri
        case name
        case title
        case mimeType
        case text
        case blob
        case meta = "_meta"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let uri = try container.decode(String.self, forKey: .uri)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        var additionalProperties = try [String: JSONValue](from: decoder)
        let meta = additionalProperties.removeValue(forKey: "_meta")
        for key in ["uri", "name", "title", "mimeType"] { additionalProperties.removeValue(forKey: key) }

        if let text = try? container.decode(String.self, forKey: .text) {
            additionalProperties.removeValue(forKey: "text")
            self = .text(uri: uri, name: name, title: title, mimeType: mimeType, text: text, meta: meta, additionalProperties: additionalProperties)
        } else if let blob = try? container.decode(String.self, forKey: .blob) {
            guard Data(base64Encoded: blob) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .blob, in: container, debugDescription: "Invalid base64 resource")
            }
            additionalProperties.removeValue(forKey: "blob")
            self = .blob(uri: uri, name: name, title: title, mimeType: mimeType, blob: blob, meta: meta, additionalProperties: additionalProperties)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "ResourceContents must have either 'text' or 'blob' field"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue]
        let uri: String
        let name: String?
        let title: String?
        let mimeType: String?
        let meta: JSONValue?
        switch self {
        case .text(let value, let displayName, let displayTitle, let mediaType, let text, let metadata, let properties):
            uri = value; name = displayName; title = displayTitle; mimeType = mediaType; meta = metadata
            object = properties
            object["text"] = .string(text)
        case .blob(let value, let displayName, let displayTitle, let mediaType, let blob, let metadata, let properties):
            uri = value; name = displayName; title = displayTitle; mimeType = mediaType; meta = metadata
            object = properties
            object["blob"] = .string(blob)
        }
        object["uri"] = .string(uri)
        object["name"] = name.map(JSONValue.string)
        object["title"] = title.map(JSONValue.string)
        object["mimeType"] = mimeType.map(JSONValue.string)
        object["_meta"] = meta
        try object.encode(to: encoder)
    }
}

// MARK: - Resource Templates

public struct ResourceTemplate: Codable, Sendable {
    public let uriTemplate: String
    public let name: String
    public let title: String?
    public let description: String?
    public let mimeType: String?

    public init(
        uriTemplate: String,
        name: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil
    ) {
        self.uriTemplate = uriTemplate
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
    }
}

public struct ListResourceTemplatesResult: Codable, Sendable {
    public let resourceTemplates: [ResourceTemplate]
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case resourceTemplates
        case meta = "_meta"
    }

    public init(resourceTemplates: [ResourceTemplate], meta: [String: JSONValue]? = nil) {
        self.resourceTemplates = resourceTemplates
        self.meta = meta
    }
}

public struct ReadResourceResult: Codable, Sendable {
    public let contents: [ResourceContents]
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case contents
        case meta = "_meta"
    }

    public init(contents: [ResourceContents], meta: [String: JSONValue]? = nil) {
        self.contents = contents
        self.meta = meta
    }
}

// MARK: - Completions

public struct CompleteRequestParams: Codable, Sendable {
    public enum Reference: Codable, Sendable {
        case prompt(name: String)
        case resource(uri: String)

        private enum CodingKeys: String, CodingKey { case type, name, uri }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "ref/prompt": self = .prompt(name: try container.decode(String.self, forKey: .name))
            case "ref/resource": self = .resource(uri: try container.decode(String.self, forKey: .uri))
            default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid completion reference")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .prompt(let name):
                try container.encode("ref/prompt", forKey: .type)
                try container.encode(name, forKey: .name)
            case .resource(let uri):
                try container.encode("ref/resource", forKey: .type)
                try container.encode(uri, forKey: .uri)
            }
        }
    }

    public struct Argument: Codable, Sendable {
        public let name: String
        public let value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    public struct Context: Codable, Sendable {
        public let arguments: [String: String]
        public init(arguments: [String: String]) { self.arguments = arguments }
    }

    public let ref: Reference
    public let argument: Argument
    public let context: Context?
    public let meta: [String: JSONValue]?
    private enum CodingKeys: String, CodingKey { case ref, argument, context; case meta = "_meta" }

    public init(ref: Reference, argument: Argument, context: Context? = nil, meta: [String: JSONValue]? = nil) {
        self.ref = ref; self.argument = argument; self.context = context; self.meta = meta
    }
}

public struct CompleteResult: Codable, Sendable {
    public struct Completion: Codable, Sendable {
        public let values: [String]
        public let total: Int?
        public let hasMore: Bool?

        public init(values: [String], total: Int? = nil, hasMore: Bool? = nil) {
            self.values = values; self.total = total; self.hasMore = hasMore
        }

        private enum CodingKeys: String, CodingKey { case values, total, hasMore }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            values = try container.decode([String].self, forKey: .values)
            guard values.count <= 100 else {
                throw DecodingError.dataCorruptedError(forKey: .values, in: container, debugDescription: "Completion must contain at most 100 values")
            }
            total = try container.decodeIfPresent(Int.self, forKey: .total)
            hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
        }
    }

    public let completion: Completion
    public let meta: [String: JSONValue]?
    private enum CodingKeys: String, CodingKey { case completion; case meta = "_meta" }
    public init(completion: Completion, meta: [String: JSONValue]? = nil) { self.completion = completion; self.meta = meta }
}

// MARK: - Prompts

public struct PromptArgument: Codable, Sendable {
    public let name: String
    public let description: String?
    public let required: Bool?

    public init(name: String, description: String? = nil, required: Bool? = nil) {
        self.name = name
        self.description = description
        self.required = required
    }
}

public struct MCPPrompt: Codable, Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let arguments: [PromptArgument]?

    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        arguments: [PromptArgument]? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
    }
}

public struct ListPromptsResult: Codable, Sendable {
    public let prompts: [MCPPrompt]
    public let nextCursor: String?
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case prompts
        case nextCursor
        case meta = "_meta"
    }

    public init(
        prompts: [MCPPrompt],
        nextCursor: String? = nil,
        meta: [String: JSONValue]? = nil
    ) {
        self.prompts = prompts
        self.nextCursor = nextCursor
        self.meta = meta
    }
}

public struct MCPPromptMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let content: ToolContent

    public init(role: Role, content: ToolContent) {
        self.role = role
        self.content = content
    }

    private enum CodingKeys: String, CodingKey { case role, content }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(ToolContent.self, forKey: .content)
        if case .unknown(.object(let raw)) = content {
            guard case .string(let type) = raw["type"], ["text", "image", "resource", "resource_link"].contains(type) else {
                throw DecodingError.dataCorruptedError(forKey: .content, in: container, debugDescription: "Unsupported prompt content type")
            }
        }
    }
}

public struct GetPromptResult: Codable, Sendable {
    public let description: String?
    public let messages: [MCPPromptMessage]
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case description
        case messages
        case meta = "_meta"
    }

    public init(description: String? = nil, messages: [MCPPromptMessage], meta: [String: JSONValue]? = nil) {
        self.description = description
        self.messages = messages
        self.meta = meta
    }
}

// MARK: - Elicitation

/// Marker type mirroring upstream Zod schema export (`ElicitationRequestSchema`).
public enum ElicitationRequestSchema: Sendable {}

/// Marker type mirroring upstream Zod schema export (`ElicitResultSchema`).
public enum ElicitResultSchema: Sendable {}

public struct ElicitationRequestParams: Codable, Sendable {
    public let message: String
    public let requestedSchema: JSONValue
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case message
        case requestedSchema
        case meta = "_meta"
    }

    public init(message: String, requestedSchema: JSONValue, meta: [String: JSONValue]? = nil) {
        self.message = message
        self.requestedSchema = requestedSchema
        self.meta = meta
    }
}

public struct ElicitationRequest: Codable, Sendable {
    public let method: String
    public let params: ElicitationRequestParams

    public init(method: String = "elicitation/create", params: ElicitationRequestParams) {
        self.method = method
        self.params = params
    }
}

public struct ElicitResult: Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case accept
        case decline
        case cancel
    }

    public let action: Action
    public let content: [String: JSONValue]?
    public let meta: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case action
        case content
        case meta = "_meta"
    }

    public init(action: Action, content: [String: JSONValue]? = nil, meta: [String: JSONValue]? = nil) {
        self.action = action
        self.content = content
        self.meta = meta
    }
}

// MARK: - Tool Call Result

/// Result of calling an MCP tool
public enum CallToolResult: Codable, Sendable {
    public var isError: Bool {
        if case .content(_, _, let isError, _) = self { return isError }
        if case .raw(.object(let object)) = self, case .bool(let value) = object["isError"] { return value }
        return false
    }

    case content(content: [ToolContent], structuredContent: JSONValue?, isError: Bool, meta: [String: JSONValue]?)
    case toolResult(result: JSONValue, meta: [String: JSONValue]?)
    case raw(JSONValue)

    enum CodingKeys: String, CodingKey {
        case content
        case structuredContent
        case isError
        case toolResult
        case meta = "_meta"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        do {
            if container.contains(.content) {
                let content = try container.decode([ToolContent].self, forKey: .content)
                let structuredContent: JSONValue? = container.contains(.structuredContent) ? try container.decode(JSONValue.self, forKey: .structuredContent) : Optional<JSONValue>.none
                let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
                let meta = try container.decodeIfPresent([String: JSONValue].self, forKey: .meta)
                self = .content(content: content, structuredContent: structuredContent, isError: isError, meta: meta)
            } else if container.contains(.structuredContent) {
                let structured = try container.decode(JSONValue.self, forKey: .structuredContent)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let text = String(decoding: try encoder.encode(structured), as: UTF8.self)
                self = .content(
                    content: [.text(.init(text: text))], structuredContent: structured,
                    isError: try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false,
                    meta: try container.decodeIfPresent([String: JSONValue].self, forKey: .meta)
                )
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Tool result must contain content, structuredContent or toolResult"))
            }
        } catch {
            guard container.contains(.toolResult) else { throw error }
            self = .toolResult(
                result: try container.decode(JSONValue.self, forKey: .toolResult),
                meta: try container.decodeIfPresent([String: JSONValue].self, forKey: .meta)
            )
        }
        if case .object(var raw) = try JSONValue(from: decoder) {
            let knownKeys: Set<String>
            if case .toolResult = self { knownKeys = ["toolResult", "_meta"] }
            else { knownKeys = ["content", "structuredContent", "isError", "_meta"] }
            if !Set(raw.keys).isSubset(of: knownKeys) {
                if case .content(let content, _, let isError, _) = self {
                    raw["isError"] = .bool(isError)
                    raw["content"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(content))
                }
                self = .raw(.object(raw))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .content(let content, let structuredContent, let isError, let meta):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(structuredContent, forKey: .structuredContent)
            if isError {
                try container.encode(isError, forKey: .isError)
            }
            try container.encodeIfPresent(meta, forKey: .meta)
        case .toolResult(let result, let meta):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(result, forKey: .toolResult)
            try container.encodeIfPresent(meta, forKey: .meta)
        case .raw(let value):
            try value.encode(to: encoder)
        }
    }
}
