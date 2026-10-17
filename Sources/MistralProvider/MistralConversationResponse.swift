import Foundation
import AISDKProvider
import AISDKProviderUtils

struct MistralConversationUsage: Decodable, Sendable {
    let value: MistralUsage

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        var fields = try container.decode(JSONObject.self)
        for key in ["prompt_tokens", "completion_tokens", "total_tokens"] where fields[key] == nil {
            fields[key] = .number(0)
        }
        value = try JSONDecoder().decode(MistralUsage.self, from: JSONEncoder().encode(fields))
    }
}

enum MistralConversationContent: Decodable, Sendable {
    case text(String)
    case thinking([ThinkingText])
    case reference(Reference)

    struct ThinkingText: Decodable, Sendable {
        enum Kind: String, Decodable { case text }
        let type: Kind
        let text: String
    }

    struct Reference: Decodable, Sendable {
        let tool: String?
        let title: String?
        let url: String?
    }

    private enum CodingKeys: String, CodingKey { case type, text, thinking }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text": self = .text(try container.decode(String.self, forKey: .text))
        case "thinking": self = .thinking(try container.decode([ThinkingText].self, forKey: .thinking))
        case "tool_reference": self = .reference(try Reference(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown conversation content type: \(type)")
        }
    }
}

enum MistralConversationMessageContent: Decodable, Sendable {
    case text(String)
    case parts([MistralConversationContent])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { self = .text(text) }
        else { self = .parts(try container.decode([MistralConversationContent].self)) }
    }

    var chunks: [MistralConversationContent] {
        switch self {
        case .text(let text): return [.text(text)]
        case .parts(let parts): return parts
        }
    }
}

struct MistralConversationToolExecution: Decodable, Sendable {
    let id: String
    let name: String
    let arguments: String
    let function: String?
    let info: JSONObject?
}

struct MistralConversationFunctionCall: Decodable, Sendable {
    enum Arguments: Decodable, Sendable {
        case text(String)
        case object(JSONObject)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { self = .text(text) }
            else { self = .object(try container.decode(JSONObject.self)) }
        }

        func stringValue() throws -> String {
            switch self {
            case .text(let text): return text
            case .object(let object): return try mistralJSONString(object)
            }
        }
    }

    let toolCallId: String
    let name: String
    let arguments: Arguments

    private enum CodingKeys: String, CodingKey {
        case toolCallId = "tool_call_id"
        case name, arguments
    }
}

struct MistralConversationResponse: Decodable, Sendable {
    enum Output: Decodable, Sendable {
        case execution(MistralConversationToolExecution)
        case functionCall(MistralConversationFunctionCall)
        case message(Message)

        struct Message: Decodable, Sendable {
            let content: MistralConversationMessageContent
            let model: String?
        }

        private enum CodingKeys: String, CodingKey { case type }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "tool.execution": self = .execution(try MistralConversationToolExecution(from: decoder))
            case "function.call": self = .functionCall(try MistralConversationFunctionCall(from: decoder))
            case "message.output": self = .message(try Message(from: decoder))
            default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown conversation output type: \(type)")
            }
        }
    }

    let conversationId: String
    let outputs: [Output]
    let usage: MistralConversationUsage?

    private enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case outputs, usage
    }
}

enum MistralConversationEvent: Decodable, Sendable {
    case started(Started)
    case done(Done)
    case error(Failure)
    case message(MessageDelta)
    case functionCall(FunctionDelta)
    case execution(ExecutionDelta)
    case executionDone(ExecutionDone)

    struct Started: Decodable, Sendable {
        let conversationId: String
        let createdAt: String?
        private enum CodingKeys: String, CodingKey {
            case conversationId = "conversation_id"
            case createdAt = "created_at"
        }
    }

    struct Done: Decodable, Sendable {
        let usage: MistralConversationUsage?
    }

    struct Failure: Decodable, Sendable {
        let message: String
        let code: Double
    }

    struct MessageDelta: Decodable, Sendable {
        enum Content: Decodable, Sendable {
            case text(String)
            case chunk(MistralConversationContent)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) { self = .text(text) }
                else { self = .chunk(try MistralConversationContent(from: decoder)) }
            }

            var chunk: MistralConversationContent {
                switch self {
                case .text(let text): return .text(text)
                case .chunk(let content): return content
                }
            }
        }

        let id: String
        let contentIndex: Double?
        let content: Content
        let model: String?
        private enum CodingKeys: String, CodingKey {
            case id, content, model
            case contentIndex = "content_index"
        }
    }

    struct FunctionDelta: Decodable, Sendable {
        let toolCallId: String
        let name: String
        let arguments: String
        let outputIndex: Int?
        private enum CodingKeys: String, CodingKey {
            case toolCallId = "tool_call_id"
            case outputIndex = "output_index"
            case name, arguments
        }
    }

    struct ExecutionDelta: Decodable, Sendable {
        let id: String
        let name: String
        let arguments: String
        let function: String?
    }

    struct ExecutionDone: Decodable, Sendable {
        let id: String
        let name: String
        let function: String?
        let info: JSONObject?
    }

    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "conversation.response.started": self = .started(try Started(from: decoder))
        case "conversation.response.done": self = .done(try Done(from: decoder))
        case "conversation.response.error": self = .error(try Failure(from: decoder))
        case "message.output.delta": self = .message(try MessageDelta(from: decoder))
        case "function.call.delta": self = .functionCall(try FunctionDelta(from: decoder))
        case "tool.execution.started", "tool.execution.delta": self = .execution(try ExecutionDelta(from: decoder))
        case "tool.execution.done": self = .executionDone(try ExecutionDone(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown conversation event type: \(type)")
        }
    }
}

let mistralConversationResponseSchema = FlexibleSchema(
    Schema<MistralConversationResponse>.codable(MistralConversationResponse.self, jsonSchema: ["type": "object"])
)
let mistralConversationEventSchema = FlexibleSchema(
    Schema<MistralConversationEvent>.codable(MistralConversationEvent.self, jsonSchema: ["type": "object"])
)
