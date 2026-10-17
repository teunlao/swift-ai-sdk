import Foundation
import AISDKProvider
import AISDKProviderUtils

enum CohereContent: Decodable, Sendable {
    case text(String)
    case thinking(String)

    private enum Keys: String, CodingKey { case type, text, thinking }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text": self = .text(try container.decode(String.self, forKey: .text))
        case "thinking": self = .thinking(try container.decode(String.self, forKey: .thinking))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown Cohere content type: \(type)")
        }
    }
}

struct CohereToolCall: Decodable, Sendable {
    enum Kind: String, Decodable { case function }
    struct Function: Decodable, Sendable {
        let name: String
        let arguments: String
    }
    let id: String
    let type: Kind
    let function: Function
}

struct CohereChatResponse: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        struct Citation: Decodable, Sendable {
            struct Source: Codable, Sendable {
                struct Document: Codable, Sendable {
                    let id: String?
                    let text: String
                    let title: String
                    private enum Keys: String, CodingKey { case id, text, title }
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: Keys.self)
                        id = container.contains(.id) ? try container.decode(String.self, forKey: .id) : nil
                        text = try container.decode(String.self, forKey: .text)
                        title = try container.decode(String.self, forKey: .title)
                    }
                }
                let type: String?
                let id: String?
                let document: Document
                private enum Keys: String, CodingKey { case type, id, document }
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: Keys.self)
                    type = container.contains(.type) ? try container.decode(String.self, forKey: .type) : nil
                    id = container.contains(.id) ? try container.decode(String.self, forKey: .id) : nil
                    document = try container.decode(Document.self, forKey: .document)
                }
            }
            let start: Double
            let end: Double
            let text: String
            let sources: [Source]
            let type: String?
            private enum Keys: String, CodingKey { case start, end, text, sources, type }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: Keys.self)
                start = try container.decode(Double.self, forKey: .start)
                end = try container.decode(Double.self, forKey: .end)
                text = try container.decode(String.self, forKey: .text)
                sources = try container.decode([Source].self, forKey: .sources)
                type = container.contains(.type) ? try container.decode(String.self, forKey: .type) : nil
            }
        }
        let role: String
        let content: [CohereContent]?
        let toolPlan: String?
        let toolCalls: [CohereToolCall]?
        let citations: [Citation]?
        private enum CodingKeys: String, CodingKey {
            case role, content, citations
            case toolPlan = "tool_plan"
            case toolCalls = "tool_calls"
        }
    }
    let generationId: String?
    let message: Message
    let finishReason: String
    let usage: CohereUsage
    private enum CodingKeys: String, CodingKey {
        case generationId = "generation_id"
        case finishReason = "finish_reason"
        case message, usage
    }
}

enum CohereChatEvent: Decodable, Sendable {
    case citationStart
    case citationEnd
    case contentStart(index: Double, content: CohereContent)
    case contentDelta(index: Double, content: ContentDelta)
    case contentEnd(index: Double)
    case messageStart(id: String?)
    case messageEnd(reason: String, usage: CohereUsage)
    case toolPlan
    case toolStart(CohereToolCall)
    case toolDelta(String)
    case toolEnd

    enum ContentDelta: Decodable, Sendable {
        case text(String)
        case thinking(String)
        private enum Keys: String, CodingKey { case text, thinking }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            if let text = try? container.decode(String.self, forKey: .text) { self = .text(text) }
            else { self = .thinking(try container.decode(String.self, forKey: .thinking)) }
        }
    }

    private enum Keys: String, CodingKey {
        case type, index, delta, message, content, id, function, arguments, usage
        case finishReason = "finish_reason"
        case toolPlan = "tool_plan"
        case toolCalls = "tool_calls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "citation-start": self = .citationStart
        case "citation-end": self = .citationEnd
        case "content-start", "content-delta":
            let index = try container.decode(Double.self, forKey: .index)
            let message = try container.nestedContainer(keyedBy: Keys.self, forKey: .delta).nestedContainer(keyedBy: Keys.self, forKey: .message)
            if type == "content-start" { self = .contentStart(index: index, content: try message.decode(CohereContent.self, forKey: .content)) }
            else { self = .contentDelta(index: index, content: try message.decode(ContentDelta.self, forKey: .content)) }
        case "content-end": self = .contentEnd(index: try container.decode(Double.self, forKey: .index))
        case "message-start": self = .messageStart(id: try container.decodeIfPresent(String.self, forKey: .id))
        case "message-end":
            let delta = try container.nestedContainer(keyedBy: Keys.self, forKey: .delta)
            self = .messageEnd(reason: try delta.decode(String.self, forKey: .finishReason), usage: try delta.decode(CohereUsage.self, forKey: .usage))
        case "tool-plan-delta", "tool-call-start", "tool-call-delta":
            let message = try container.nestedContainer(keyedBy: Keys.self, forKey: .delta).nestedContainer(keyedBy: Keys.self, forKey: .message)
            if type == "tool-plan-delta" {
                _ = try message.decode(String.self, forKey: .toolPlan)
                self = .toolPlan
            } else if type == "tool-call-start" {
                self = .toolStart(try message.decode(CohereToolCall.self, forKey: .toolCalls))
            } else {
                let function = try message.nestedContainer(keyedBy: Keys.self, forKey: .toolCalls).nestedContainer(keyedBy: Keys.self, forKey: .function)
                self = .toolDelta(try function.decode(String.self, forKey: .arguments))
            }
        case "tool-call-end": self = .toolEnd
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown Cohere event type: \(type)")
        }
    }
}

let cohereChatResponseSchema = FlexibleSchema(Schema<CohereChatResponse>.codable(CohereChatResponse.self, jsonSchema: ["type": "object"]))
let cohereChatEventSchema = FlexibleSchema(Schema<CohereChatEvent>.codable(CohereChatEvent.self, jsonSchema: ["type": "object"]))
