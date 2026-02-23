import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Request Models

public struct AnthropicMessagesPrompt: Sendable, Equatable, Encodable {
    public var system: [JSONValue]?
    public var messages: [AnthropicMessage]

    public init(system: [JSONValue]? = nil, messages: [AnthropicMessage]) {
        self.system = system
        self.messages = messages
    }

    public func toJSONObject() -> [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "messages": .array(messages.map { $0.toJSONValue() })
        ]
        if let system {
            payload["system"] = .array(system)
        }
        return payload
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(toJSONObject())
    }
}

public struct AnthropicMessage: Sendable, Equatable, Encodable {
    public var role: String
    public var content: [JSONValue]

    public init(role: String, content: [JSONValue]) {
        self.role = role
        self.content = content
    }

    public func toJSONValue() -> JSONValue {
        .object([
            "role": .string(role),
            "content": .array(content)
        ])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(toJSONValue())
    }
}

// MARK: - Response Models

public struct AnthropicMessagesResponse: Codable, Sendable {
    public let type: String
    public let id: String?
    public let model: String?
    public let content: [AnthropicMessageContent]
    public let stopReason: String?
    public let stopSequence: String?
    public let usage: AnthropicUsage
    public let container: AnthropicContainer?
    public let contextManagement: AnthropicResponseContextManagement?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case model
        case content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
        case container
        case contextManagement = "context_management"
    }
}

public struct AnthropicContainer: Codable, Sendable {
    public struct Skill: Codable, Sendable {
        public let type: String
        public let skillId: String
        public let version: String

        enum CodingKeys: String, CodingKey {
            case type
            case skillId = "skill_id"
            case version
        }
    }

    public let expiresAt: String
    public let id: String
    public let skills: [Skill]?

    enum CodingKeys: String, CodingKey {
        case expiresAt = "expires_at"
        case id
        case skills
    }
}

public struct AnthropicResponseContextManagement: Codable, Sendable {
    public enum AppliedEdit: Codable, Sendable {
        case clearToolUses20250919(ClearToolUses20250919)
        case clearThinking20251015(ClearThinking20251015)
        case compact20260112(Compact20260112)

        enum CodingKeys: String, CodingKey {
            case type
        }

        enum EditType: String {
            case clearToolUses20250919 = "clear_tool_uses_20250919"
            case clearThinking20251015 = "clear_thinking_20251015"
            case compact20260112 = "compact_20260112"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawType = try container.decode(String.self, forKey: .type)
            guard let type = EditType(rawValue: rawType) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unsupported context management edit type: \(rawType)"
                )
            }

            let single = try decoder.singleValueContainer()
            switch type {
            case .clearToolUses20250919:
                self = .clearToolUses20250919(try single.decode(ClearToolUses20250919.self))
            case .clearThinking20251015:
                self = .clearThinking20251015(try single.decode(ClearThinking20251015.self))
            case .compact20260112:
                self = .compact20260112(try single.decode(Compact20260112.self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .clearToolUses20250919(let value):
                try value.encode(to: encoder)
            case .clearThinking20251015(let value):
                try value.encode(to: encoder)
            case .compact20260112(let value):
                try value.encode(to: encoder)
            }
        }
    }

    public struct ClearToolUses20250919: Codable, Sendable {
        public let type: String
        public let clearedToolUses: Int
        public let clearedInputTokens: Int

        enum CodingKeys: String, CodingKey {
            case type
            case clearedToolUses = "cleared_tool_uses"
            case clearedInputTokens = "cleared_input_tokens"
        }
    }

    public struct ClearThinking20251015: Codable, Sendable {
        public let type: String
        public let clearedThinkingTurns: Int
        public let clearedInputTokens: Int

        enum CodingKeys: String, CodingKey {
            case type
            case clearedThinkingTurns = "cleared_thinking_turns"
            case clearedInputTokens = "cleared_input_tokens"
        }
    }

    public struct Compact20260112: Codable, Sendable {
        public let type: String
    }

    public let appliedEdits: [AppliedEdit]

    enum CodingKeys: String, CodingKey {
        case appliedEdits = "applied_edits"
    }
}

public struct AnthropicUsage: Codable, Sendable {
    public struct CacheCreation: Codable, Sendable {
        public let ephemeral5mInputTokens: Int?
        public let ephemeral1hInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        }
    }

    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?
    public let cacheCreation: CacheCreation?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation = "cache_creation"
    }
}

public enum AnthropicMessageContent: Codable, Sendable {
    case text(TextContent)
    case thinking(ThinkingContent)
    case redactedThinking(RedactedThinkingContent)
    case toolUse(ToolUseContent)
    case serverToolUse(ServerToolUseContent)
    case mcpToolUse(McpToolUseContent)
    case mcpToolResult(McpToolResultContent)
    case toolSearchToolResult(ToolSearchToolResultContent)
    case webFetchResult(WebFetchToolResultContent)
    case webSearchResult(WebSearchToolResultContent)
    case codeExecutionResult(CodeExecutionToolResultContent)
    case textEditorCodeExecutionResult(CodeExecutionToolResultContent)
    case bashCodeExecutionResult(CodeExecutionToolResultContent)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum ContentType: String {
        case text
        case thinking
        case redactedThinking = "redacted_thinking"
        case toolUse = "tool_use"
        case serverToolUse = "server_tool_use"
        case mcpToolUse = "mcp_tool_use"
        case mcpToolResult = "mcp_tool_result"
        case toolSearchToolResult = "tool_search_tool_result"
        case webFetchToolResult = "web_fetch_tool_result"
        case webSearchToolResult = "web_search_tool_result"
        case codeExecutionToolResult = "code_execution_tool_result"
        case textEditorCodeExecutionToolResult = "text_editor_code_execution_tool_result"
        case bashCodeExecutionToolResult = "bash_code_execution_tool_result"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let type = ContentType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported content type: \(rawType)")
        }

        let singleValue = try decoder.singleValueContainer()
        switch type {
        case .text:
            self = .text(try singleValue.decode(TextContent.self))
        case .thinking:
            self = .thinking(try singleValue.decode(ThinkingContent.self))
        case .redactedThinking:
            self = .redactedThinking(try singleValue.decode(RedactedThinkingContent.self))
        case .toolUse:
            self = .toolUse(try singleValue.decode(ToolUseContent.self))
        case .serverToolUse:
            self = .serverToolUse(try singleValue.decode(ServerToolUseContent.self))
        case .mcpToolUse:
            self = .mcpToolUse(try singleValue.decode(McpToolUseContent.self))
        case .mcpToolResult:
            self = .mcpToolResult(try singleValue.decode(McpToolResultContent.self))
        case .toolSearchToolResult:
            self = .toolSearchToolResult(try singleValue.decode(ToolSearchToolResultContent.self))
        case .webFetchToolResult:
            self = .webFetchResult(try singleValue.decode(WebFetchToolResultContent.self))
        case .webSearchToolResult:
            self = .webSearchResult(try singleValue.decode(WebSearchToolResultContent.self))
        case .codeExecutionToolResult:
            self = .codeExecutionResult(try singleValue.decode(CodeExecutionToolResultContent.self))
        case .textEditorCodeExecutionToolResult:
            self = .textEditorCodeExecutionResult(try singleValue.decode(CodeExecutionToolResultContent.self))
        case .bashCodeExecutionToolResult:
            self = .bashCodeExecutionResult(try singleValue.decode(CodeExecutionToolResultContent.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value):
            try value.encode(to: encoder)
        case .thinking(let value):
            try value.encode(to: encoder)
        case .redactedThinking(let value):
            try value.encode(to: encoder)
        case .toolUse(let value):
            try value.encode(to: encoder)
        case .serverToolUse(let value):
            try value.encode(to: encoder)
        case .mcpToolUse(let value):
            try value.encode(to: encoder)
        case .mcpToolResult(let value):
            try value.encode(to: encoder)
        case .toolSearchToolResult(let value):
            try value.encode(to: encoder)
        case .webFetchResult(let value):
            try value.encode(to: encoder)
        case .webSearchResult(let value):
            try value.encode(to: encoder)
        case .codeExecutionResult(let value):
            try value.encode(to: encoder)
        case .textEditorCodeExecutionResult(let value):
            try value.encode(to: encoder)
        case .bashCodeExecutionResult(let value):
            try value.encode(to: encoder)
        }
    }
}

public struct TextContent: Codable, Sendable {
    public let type: String
    public let text: String
    public let citations: [AnthropicCitation]?
}

public struct ThinkingContent: Codable, Sendable {
    public let type: String
    public let thinking: String
    public let signature: String?
}

public struct RedactedThinkingContent: Codable, Sendable {
    public let type: String
    public let data: String
}

public struct ToolUseContent: Codable, Sendable {
    public struct Caller: Codable, Sendable {
        public let type: String
        public let toolId: String?

        enum CodingKeys: String, CodingKey {
            case type
            case toolId = "tool_id"
        }
    }

    public let type: String
    public let id: String
    public let name: String
    public let input: JSONValue?
    public let caller: Caller?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case input
        case caller
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        input = try? container.decode(JSONValue.self, forKey: .input)
        caller = try? container.decode(Caller.self, forKey: .caller)
    }
}

public struct ServerToolUseContent: Codable, Sendable {
    public let type: String
    public let id: String
    public let name: String
    public let input: JSONValue?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case input
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        input = try? container.decode(JSONValue.self, forKey: .input)
    }
}

public struct McpToolUseContent: Codable, Sendable {
    public let type: String
    public let id: String
    public let name: String
    public let serverName: String
    public let input: JSONValue?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case serverName = "server_name"
        case input
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        serverName = try container.decode(String.self, forKey: .serverName)
        input = try? container.decode(JSONValue.self, forKey: .input)
    }
}

public struct McpToolResultContent: Codable, Sendable {
    public let type: String
    public let toolUseId: String
    public let isError: Bool
    public let content: JSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case isError = "is_error"
        case content
    }
}

public struct ToolSearchToolResultContent: Codable, Sendable {
    public let type: String
    public let toolUseId: String
    public let content: JSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
    }
}

public struct WebFetchToolResultContent: Codable, Sendable {
    public struct DocumentContent: Codable, Sendable {
        public struct Source: Codable, Sendable {
            public let type: String
            public let mediaType: String
            public let data: String

            enum CodingKeys: String, CodingKey {
                case type
                case mediaType = "media_type"
                case data
            }
        }

        public let type: String
        public let title: String?
        public let citations: Citations?
        public let source: Source

        public struct Citations: Codable, Sendable {
            public let enabled: Bool
        }
    }

    public struct Content: Codable, Sendable {
        public let type: String
        public let url: String
        public let retrievedAt: String?
        public let content: DocumentContent

        enum CodingKeys: String, CodingKey {
            case type
            case url
            case retrievedAt = "retrieved_at"
            case content
        }
    }

    public let type: String
    public let toolUseId: String
    public let content: JSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
    }
}

public struct WebSearchToolResultContent: Codable, Sendable {
    public let type: String
    public let toolUseId: String
    public let content: JSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
    }
}

public struct CodeExecutionToolResultContent: Codable, Sendable {
    public let type: String
    public let toolUseId: String
    public let content: JSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
    }
}

public enum AnthropicCitation: Codable, Sendable {
    case webSearchResultLocation(WebSearchResultLocation)
    case pageLocation(PageLocation)
    case charLocation(CharLocation)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum CitationType: String {
        case webSearchResultLocation = "web_search_result_location"
        case pageLocation = "page_location"
        case charLocation = "char_location"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let type = CitationType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported citation type: \(rawType)")
        }
        let single = try decoder.singleValueContainer()
        switch type {
        case .webSearchResultLocation:
            self = .webSearchResultLocation(try single.decode(WebSearchResultLocation.self))
        case .pageLocation:
            self = .pageLocation(try single.decode(PageLocation.self))
        case .charLocation:
            self = .charLocation(try single.decode(CharLocation.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .webSearchResultLocation(let value):
            try value.encode(to: encoder)
        case .pageLocation(let value):
            try value.encode(to: encoder)
        case .charLocation(let value):
            try value.encode(to: encoder)
        }
    }
}

public struct WebSearchResultLocation: Codable, Sendable {
    public let type: String
    public let citedText: String
    public let url: String
    public let title: String
    public let encryptedIndex: String

    enum CodingKeys: String, CodingKey {
        case type
        case citedText = "cited_text"
        case url
        case title
        case encryptedIndex = "encrypted_index"
    }
}

public struct PageLocation: Codable, Sendable {
    public let type: String
    public let citedText: String
    public let documentIndex: Int
    public let documentTitle: String?
    public let startPageNumber: Int
    public let endPageNumber: Int

    enum CodingKeys: String, CodingKey {
        case type
        case citedText = "cited_text"
        case documentIndex = "document_index"
        case documentTitle = "document_title"
        case startPageNumber = "start_page_number"
        case endPageNumber = "end_page_number"
    }
}

public struct CharLocation: Codable, Sendable {
    public let type: String
    public let citedText: String
    public let documentIndex: Int
    public let documentTitle: String?
    public let startCharIndex: Int
    public let endCharIndex: Int

    enum CodingKeys: String, CodingKey {
        case type
        case citedText = "cited_text"
        case documentIndex = "document_index"
        case documentTitle = "document_title"
        case startCharIndex = "start_char_index"
        case endCharIndex = "end_char_index"
    }
}

// MARK: - Stream Events

public enum AnthropicStreamEvent: Codable, Sendable {
    case messageStart(MessageStart)
    case contentBlockStart(ContentBlockStart)
    case contentBlockDelta(ContentBlockDelta)
    case contentBlockStop(ContentBlockStop)
    case error(StreamError)
    case messageDelta(MessageDelta)
    case messageStop
    case ping

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum EventType: String {
        case messageStart = "message_start"
        case contentBlockStart = "content_block_start"
        case contentBlockDelta = "content_block_delta"
        case contentBlockStop = "content_block_stop"
        case error
        case messageDelta = "message_delta"
        case messageStop = "message_stop"
        case ping
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let type = EventType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported stream event: \(rawType)")
        }
        let single = try decoder.singleValueContainer()
        switch type {
        case .messageStart:
            self = .messageStart(try single.decode(MessageStart.self))
        case .contentBlockStart:
            self = .contentBlockStart(try single.decode(ContentBlockStart.self))
        case .contentBlockDelta:
            self = .contentBlockDelta(try single.decode(ContentBlockDelta.self))
        case .contentBlockStop:
            self = .contentBlockStop(try single.decode(ContentBlockStop.self))
        case .error:
            self = .error(try single.decode(StreamError.self))
        case .messageDelta:
            self = .messageDelta(try single.decode(MessageDelta.self))
        case .messageStop:
            self = .messageStop
        case .ping:
            self = .ping
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .messageStart(let value): try value.encode(to: encoder)
        case .contentBlockStart(let value): try value.encode(to: encoder)
        case .contentBlockDelta(let value): try value.encode(to: encoder)
        case .contentBlockStop(let value): try value.encode(to: encoder)
        case .error(let value): try value.encode(to: encoder)
        case .messageDelta(let value): try value.encode(to: encoder)
        case .messageStop:
            var container = encoder.singleValueContainer()
            try container.encode(["type": "message_stop"])
        case .ping:
            var container = encoder.singleValueContainer()
            try container.encode(["type": "ping"])
        }
    }
}

public struct MessageStart: Codable, Sendable {
    public struct MessageInfo: Codable, Sendable {
        public let id: String?
        public let model: String?
        public let content: [AnthropicMessageContent]?
        public let usage: AnthropicUsage?
        public let container: AnthropicContainer?
        public let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case id
            case model
            case content
            case usage
            case container
            case stopReason = "stop_reason"
        }
    }

    public let type: String
    public let message: MessageInfo
}

public struct ContentBlockStart: Codable, Sendable {
    public let type: String
    public let index: Int
    public let contentBlock: AnthropicMessageContent

    enum CodingKeys: String, CodingKey {
        case type
        case index
        case contentBlock = "content_block"
    }
}

public struct ContentBlockDelta: Codable, Sendable {
    public enum Delta: Codable, Sendable {
        case inputJSONDelta(String)
        case textDelta(String)
        case thinkingDelta(String)
        case signatureDelta(String)
        case citationsDelta(AnthropicCitation)

        enum CodingKeys: String, CodingKey {
            case type
        }

        enum DeltaType: String {
            case inputJSONDelta = "input_json_delta"
            case textDelta = "text_delta"
            case thinkingDelta = "thinking_delta"
            case signatureDelta = "signature_delta"
            case citationsDelta = "citations_delta"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawType = try container.decode(String.self, forKey: .type)
            guard let type = DeltaType(rawValue: rawType) else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported delta type: \(rawType)")
            }
            let single = try decoder.singleValueContainer()
            switch type {
            case .inputJSONDelta:
                let wrapper = try single.decode(InputJSONDelta.self)
                self = .inputJSONDelta(wrapper.partialJSON)
            case .textDelta:
                let wrapper = try single.decode(TextDelta.self)
                self = .textDelta(wrapper.text)
            case .thinkingDelta:
                let wrapper = try single.decode(ThinkingDelta.self)
                self = .thinkingDelta(wrapper.thinking)
            case .signatureDelta:
                let wrapper = try single.decode(SignatureDelta.self)
                self = .signatureDelta(wrapper.signature)
            case .citationsDelta:
                let wrapper = try single.decode(CitationsDelta.self)
                self = .citationsDelta(wrapper.citation)
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .inputJSONDelta(let json):
                try InputJSONDelta(partialJSON: json).encode(to: encoder)
            case .textDelta(let text):
                try TextDelta(text: text).encode(to: encoder)
            case .thinkingDelta(let thinking):
                try ThinkingDelta(thinking: thinking).encode(to: encoder)
            case .signatureDelta(let signature):
                try SignatureDelta(signature: signature).encode(to: encoder)
            case .citationsDelta(let citation):
                try CitationsDelta(citation: citation).encode(to: encoder)
            }
        }

        private struct InputJSONDelta: Codable, Sendable {
            let type = "input_json_delta"
            let partialJSON: String

            enum CodingKeys: String, CodingKey {
                case type
                case partialJSON = "partial_json"
            }
        }

        private struct TextDelta: Codable, Sendable {
            let type = "text_delta"
            let text: String

            enum CodingKeys: String, CodingKey {
                case type, text
            }
        }

        private struct ThinkingDelta: Codable, Sendable {
            let type = "thinking_delta"
            let thinking: String

            enum CodingKeys: String, CodingKey {
                case type, thinking
            }
        }

        private struct SignatureDelta: Codable, Sendable {
            let type = "signature_delta"
            let signature: String

            enum CodingKeys: String, CodingKey {
                case type, signature
            }
        }

        private struct CitationsDelta: Codable, Sendable {
            let type = "citations_delta"
            let citation: AnthropicCitation

            enum CodingKeys: String, CodingKey {
                case type, citation
            }
        }
    }

    public let type: String
    public let index: Int
    public let delta: Delta
}

public struct ContentBlockStop: Codable, Sendable {
    public let type: String
    public let index: Int
}

public struct StreamError: Codable, Sendable {
    public struct Payload: Codable, Sendable {
        public let type: String
        public let message: String
    }

    public let type: String
    public let error: Payload
}

public struct MessageDelta: Codable, Sendable {
    public struct Delta: Codable, Sendable {
        public let stopReason: String?
        public let stopSequence: String?
        public let container: AnthropicContainer?

        enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
            case stopSequence = "stop_sequence"
            case container
        }
    }

    public let type: String
    public let delta: Delta
    public let usage: AnthropicUsage?
    public let contextManagement: AnthropicResponseContextManagement?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case usage
        case contextManagement = "context_management"
    }
}

// MARK: - Reasoning Metadata

public struct AnthropicReasoningMetadata: Codable, Sendable {
    public let signature: String?
    public let redactedData: String?

    enum CodingKeys: String, CodingKey {
        case signature
        case redactedData = "redactedData"
    }
}

// MARK: - Reasoning Metadata Schema

private let anthropicReasoningMetadataJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "signature": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "redactedData": .object([
            "type": .array([.string("string"), .string("null")])
        ])
    ]),
    "additionalProperties": .bool(true)
])

public let anthropicReasoningMetadataSchema = FlexibleSchema(
    Schema<AnthropicReasoningMetadata>.codable(
        AnthropicReasoningMetadata.self,
        jsonSchema: anthropicReasoningMetadataJSONSchema
    )
)

// MARK: - Schemas

public let anthropicMessagesResponseSchema = FlexibleSchema(
    Schema.codable(
        AnthropicMessagesResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

public let anthropicMessagesChunkSchema = FlexibleSchema(
    Schema.codable(
        AnthropicStreamEvent.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
