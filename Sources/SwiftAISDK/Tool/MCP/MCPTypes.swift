/**
 Model Context Protocol (MCP) type definitions.

 Port of `@ai-sdk/ai/src/tool/mcp/types.ts`.

 This module defines the core types for the Model Context Protocol, including
 protocol versioning, tool schemas, server capabilities, and result types.
 */

import Foundation

// MARK: - Protocol Versioning

/// Latest supported MCP protocol version
public let latestProtocolVersion = "2025-06-18"

/// All supported MCP protocol versions (newest to oldest)
public let supportedProtocolVersions = [
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
]

// MARK: - Tool Schemas

/// Tool schema definitions for MCP tools.
/// Can be explicit schemas or "automatic" for dynamic discovery.
public enum ToolSchemas {
    case automatic
    case schemas([String: ToolSchemaDefinition])
}

/// Definition of a tool schema (user-facing API)
public struct ToolSchemaDefinition: Sendable {
    public let inputSchema: FlexibleSchema<[String: JSONValue]>

    public init(inputSchema: FlexibleSchema<[String: JSONValue]>) {
        self.inputSchema = inputSchema
    }
}

// MARK: - Base Types

/// Client or server implementation metadata
public struct Configuration: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
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
    /// Maximum total timeout across all retries
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

/// Server capabilities describing what the MCP server supports
public struct ServerCapabilities: Codable, Sendable {
    public let experimental: [String: JSONValue]?
    public let logging: [String: JSONValue]?
    public let prompts: PromptsCapabilities?
    public let resources: ResourcesCapabilities?
    public let tools: ToolsCapabilities?

    public init(
        experimental: [String: JSONValue]? = nil,
        logging: [String: JSONValue]? = nil,
        prompts: PromptsCapabilities? = nil,
        resources: ResourcesCapabilities? = nil,
        tools: ToolsCapabilities? = nil
    ) {
        self.experimental = experimental
        self.logging = logging
        self.prompts = prompts
        self.resources = resources
        self.tools = tools
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

/// MCP tool definition (from wire protocol)
public struct MCPTool: Codable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONValue

    public init(name: String, description: String? = nil, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
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

// MARK: - Content Types

/// Content types that can be returned from tool calls
public enum ToolContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResource)

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
            self = .image(try ImageContent(from: decoder))
        case "resource":
            self = .resource(try EmbeddedResource(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
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
        }
    }
}

/// Resource contents (text or blob)
public enum ResourceContents: Codable, Sendable {
    case text(uri: String, mimeType: String?, text: String)
    case blob(uri: String, mimeType: String?, blob: String) // base64

    enum CodingKeys: String, CodingKey {
        case uri
        case mimeType
        case text
        case blob
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let uri = try container.decode(String.self, forKey: .uri)
        let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)

        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(uri: uri, mimeType: mimeType, text: text)
        } else if let blob = try container.decodeIfPresent(String.self, forKey: .blob) {
            self = .blob(uri: uri, mimeType: mimeType, blob: blob)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "ResourceContents must have either 'text' or 'blob' field"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let uri, let mimeType, let text):
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encode(text, forKey: .text)
        case .blob(let uri, let mimeType, let blob):
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encode(blob, forKey: .blob)
        }
    }
}

// MARK: - Tool Call Result

/// Result of calling an MCP tool
public enum CallToolResult: Codable, Sendable {
    case content(content: [ToolContent], isError: Bool, meta: [String: JSONValue]?)
    case toolResult(result: JSONValue, meta: [String: JSONValue]?)

    enum CodingKeys: String, CodingKey {
        case content
        case isError
        case toolResult
        case meta = "_meta"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.content) {
            let content = try container.decode([ToolContent].self, forKey: .content)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            let meta = try container.decodeIfPresent([String: JSONValue].self, forKey: .meta)
            self = .content(content: content, isError: isError, meta: meta)
        } else if container.contains(.toolResult) {
            let result = try container.decode(JSONValue.self, forKey: .toolResult)
            let meta = try container.decodeIfPresent([String: JSONValue].self, forKey: .meta)
            self = .toolResult(result: result, meta: meta)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .content,
                in: container,
                debugDescription: "CallToolResult must have either 'content' or 'toolResult' field"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .content(let content, let isError, let meta):
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(isError, forKey: .isError)
            }
            try container.encodeIfPresent(meta, forKey: .meta)
        case .toolResult(let result, let meta):
            try container.encode(result, forKey: .toolResult)
            try container.encodeIfPresent(meta, forKey: .meta)
        }
    }
}
