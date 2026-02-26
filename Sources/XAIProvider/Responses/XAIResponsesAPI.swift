import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias XAIResponsesInput = [JSONValue]

public struct XAIResponsesUsage: Codable, Sendable, Equatable {
    public struct InputTokensDetails: Codable, Sendable, Equatable {
        public let cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    public struct OutputTokensDetails: Codable, Sendable, Equatable {
        public let reasoningTokens: Int?

        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }

    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int?
    public let inputTokensDetails: InputTokensDetails?
    public let outputTokensDetails: OutputTokensDetails?
    public let numSourcesUsed: Int?
    public let numServerSideToolsUsed: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokensDetails = "output_tokens_details"
        case numSourcesUsed = "num_sources_used"
        case numServerSideToolsUsed = "num_server_side_tools_used"
    }
}

public struct XAIResponsesResponse: Codable, Sendable, Equatable {
    public let id: String?
    public let createdAt: Double?
    public let model: String?
    public let object: String
    public let output: [XAIResponsesOutputItem]
    public let usage: XAIResponsesUsage?
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case model
        case object
        case output
        case usage
        case status
    }
}

public struct XAIResponsesStreamResponse: Codable, Sendable, Equatable {
    public let id: String?
    public let createdAt: Double?
    public let model: String?
    public let object: String?
    public let output: [XAIResponsesOutputItem]
    public let usage: XAIResponsesUsage?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case model
        case object
        case output
        case usage
        case status
    }
}

public enum XAIResponsesAnnotation: Codable, Sendable, Equatable {
    case urlCitation(url: String, title: String?)
    case other(type: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        if type == "url_citation" {
            let url = try container.decode(String.self, forKey: .url)
            let title = try container.decodeIfPresent(String.self, forKey: .title)
            self = .urlCitation(url: url, title: title)
        } else {
            self = .other(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .urlCitation(let url, let title):
            try container.encode("url_citation", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(title, forKey: .title)
        case .other(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

public struct XAIResponsesMessageContentPart: Codable, Sendable, Equatable {
    public let type: String
    public let text: String?
    public let annotations: [XAIResponsesAnnotation]?
}

public struct XAIResponsesReasoningSummaryPart: Codable, Sendable, Equatable {
    public let type: String
    public let text: String
}

public struct XAIResponsesToolCall: Codable, Sendable, Equatable {
    public let type: String
    public let id: String
    public let status: String
    public let queries: [String]?
    public let results: [XAIResponsesFileSearchResult]?

    // Common tool-call payload fields:
    public let name: String?
    public let arguments: String?
    public let input: String?
    public let callId: String?
    public let action: JSONValue?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case status
        case queries
        case results
        case name
        case arguments
        case input
        case callId = "call_id"
        case action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        queries = try container.decodeIfPresent([String].self, forKey: .queries)
        results = try container.decodeIfPresent([XAIResponsesFileSearchResult].self, forKey: .results)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments)
        input = try container.decodeIfPresent(String.self, forKey: .input)
        callId = try container.decodeIfPresent(String.self, forKey: .callId)
        action = try container.decodeIfPresent(JSONValue.self, forKey: .action)
    }
}

public struct XAIResponsesFileSearchResult: Codable, Sendable, Equatable {
    public let fileId: String
    public let filename: String
    public let score: Double
    public let text: String

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case filename
        case score
        case text
    }
}

public struct XAIResponsesMCPCall: Codable, Sendable, Equatable {
    public let type: String
    public let id: String
    public let status: String
    public let name: String?
    public let arguments: String?
    public let output: String?
    public let error: String?
    public let serverLabel: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case status
        case name
        case arguments
        case output
        case error
        case serverLabel = "server_label"
    }
}

public struct XAIResponsesMessage: Codable, Sendable, Equatable {
    public let type: String
    public let role: String
    public let content: [XAIResponsesMessageContentPart]
    public let id: String
    public let status: String
}

public struct XAIResponsesFunctionCall: Codable, Sendable, Equatable {
    public let type: String
    public let name: String
    public let arguments: String
    public let callId: String
    public let id: String

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case arguments
        case callId = "call_id"
        case id
    }
}

public struct XAIResponsesReasoning: Codable, Sendable, Equatable {
    public let type: String
    public let id: String
    public let summary: [XAIResponsesReasoningSummaryPart]
    public let status: String
    public let encryptedContent: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case summary
        case status
        case encryptedContent = "encrypted_content"
    }
}

public enum XAIResponsesOutputItem: Codable, Sendable, Equatable {
    case toolCall(XAIResponsesToolCall)
    case message(XAIResponsesMessage)
    case functionCall(XAIResponsesFunctionCall)
    case reasoning(XAIResponsesReasoning)
    case mcpCall(XAIResponsesMCPCall)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public var type: String {
        switch self {
        case .toolCall(let value): value.type
        case .message(let value): value.type
        case .functionCall(let value): value.type
        case .reasoning(let value): value.type
        case .mcpCall(let value): value.type
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "web_search_call",
             "x_search_call",
             "code_interpreter_call",
             "code_execution_call",
             "view_image_call",
             "view_x_video_call",
             "file_search_call",
             "custom_tool_call":
            self = .toolCall(try XAIResponsesToolCall(from: decoder))
        case "mcp_call":
            self = .mcpCall(try XAIResponsesMCPCall(from: decoder))
        case "message":
            self = .message(try XAIResponsesMessage(from: decoder))
        case "function_call":
            self = .functionCall(try XAIResponsesFunctionCall(from: decoder))
        case "reasoning":
            self = .reasoning(try XAIResponsesReasoning(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown xAI responses output item type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .toolCall(let value):
            try value.encode(to: encoder)
        case .mcpCall(let value):
            try value.encode(to: encoder)
        case .message(let value):
            try value.encode(to: encoder)
        case .functionCall(let value):
            try value.encode(to: encoder)
        case .reasoning(let value):
            try value.encode(to: encoder)
        }
    }
}

public enum XAIResponsesChunk: Codable, Sendable, Equatable {
    case responseCreated(response: XAIResponsesStreamResponse)
    case responseInProgress(response: XAIResponsesStreamResponse)

    case responseOutputItemAdded(item: XAIResponsesOutputItem, outputIndex: Int)
    case responseOutputItemDone(item: XAIResponsesOutputItem, outputIndex: Int)

    case responseContentPartAdded(itemId: String, outputIndex: Int, contentIndex: Int, part: XAIResponsesMessageContentPart)
    case responseContentPartDone(itemId: String, outputIndex: Int, contentIndex: Int, part: XAIResponsesMessageContentPart)

    case responseOutputTextDelta(itemId: String, outputIndex: Int, contentIndex: Int, delta: String)
    case responseOutputTextDone(itemId: String, outputIndex: Int, contentIndex: Int, text: String, annotations: [XAIResponsesAnnotation]?)
    case responseOutputTextAnnotationAdded(itemId: String, outputIndex: Int, contentIndex: Int, annotationIndex: Int, annotation: XAIResponsesAnnotation)

    case responseReasoningSummaryPartAdded(itemId: String, outputIndex: Int, summaryIndex: Int, part: XAIResponsesReasoningSummaryPart)
    case responseReasoningSummaryPartDone(itemId: String, outputIndex: Int, summaryIndex: Int, part: XAIResponsesReasoningSummaryPart)
    case responseReasoningSummaryTextDelta(itemId: String, outputIndex: Int, summaryIndex: Int, delta: String)
    case responseReasoningSummaryTextDone(itemId: String, outputIndex: Int, summaryIndex: Int, text: String)

    case responseReasoningTextDelta(itemId: String, outputIndex: Int, contentIndex: Int, delta: String)
    case responseReasoningTextDone(itemId: String, outputIndex: Int, contentIndex: Int, text: String)

    case responseCustomToolCallInputDelta(itemId: String, outputIndex: Int, delta: String)
    case responseCustomToolCallInputDone(itemId: String, outputIndex: Int, input: String)

    case responseFunctionCallArgumentsDelta(itemId: String, outputIndex: Int, delta: String)
    case responseFunctionCallArgumentsDone(itemId: String, outputIndex: Int, arguments: String)

    case responseMcpCallArgumentsDelta(itemId: String, outputIndex: Int, delta: String)
    case responseMcpCallArgumentsDone(itemId: String, outputIndex: Int, arguments: String?)
    case responseMcpCallOutputDelta(itemId: String, outputIndex: Int, delta: String)
    case responseMcpCallOutputDone(itemId: String, outputIndex: Int, output: String?)

    case responseDone(response: XAIResponsesResponse)
    case responseCompleted(response: XAIResponsesResponse)

    // Status/progress events (ignored by the model implementation but validated)
    case responseWebSearchCallStatus(type: String, itemId: String, outputIndex: Int)
    case responseXSearchCallStatus(type: String, itemId: String, outputIndex: Int)
    case responseFileSearchCallStatus(type: String, itemId: String, outputIndex: Int)
    case responseCodeExecutionCallStatus(type: String, itemId: String, outputIndex: Int)
    case responseCodeInterpreterCallStatus(type: String, itemId: String, outputIndex: Int)
    case responseCodeInterpreterCallCodeDelta(itemId: String, outputIndex: Int, delta: String)
    case responseCodeInterpreterCallCodeDone(itemId: String, outputIndex: Int, code: String)
    case responseMcpCallStatus(type: String, itemId: String, outputIndex: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case response
        case item
        case outputIndex = "output_index"
        case itemId = "item_id"
        case contentIndex = "content_index"
        case summaryIndex = "summary_index"
        case annotationIndex = "annotation_index"
        case annotations
        case annotation
        case part
        case delta
        case text
        case code
        case input
        case arguments
        case output
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "response.created":
            self = .responseCreated(response: try container.decode(XAIResponsesStreamResponse.self, forKey: .response))

        case "response.in_progress":
            self = .responseInProgress(response: try container.decode(XAIResponsesStreamResponse.self, forKey: .response))

        case "response.output_item.added":
            self = .responseOutputItemAdded(
                item: try container.decode(XAIResponsesOutputItem.self, forKey: .item),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        case "response.output_item.done":
            self = .responseOutputItemDone(
                item: try container.decode(XAIResponsesOutputItem.self, forKey: .item),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        case "response.content_part.added":
            self = .responseContentPartAdded(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                part: try container.decode(XAIResponsesMessageContentPart.self, forKey: .part)
            )

        case "response.content_part.done":
            self = .responseContentPartDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                part: try container.decode(XAIResponsesMessageContentPart.self, forKey: .part)
            )

        case "response.output_text.delta":
            self = .responseOutputTextDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.output_text.done":
            self = .responseOutputTextDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                text: try container.decode(String.self, forKey: .text),
                annotations: try container.decodeIfPresent([XAIResponsesAnnotation].self, forKey: .annotations)
            )

        case "response.output_text.annotation.added":
            self = .responseOutputTextAnnotationAdded(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                annotationIndex: try container.decode(Int.self, forKey: .annotationIndex),
                annotation: try container.decode(XAIResponsesAnnotation.self, forKey: .annotation)
            )

        case "response.reasoning_summary_part.added":
            self = .responseReasoningSummaryPartAdded(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                summaryIndex: try container.decode(Int.self, forKey: .summaryIndex),
                part: try container.decode(XAIResponsesReasoningSummaryPart.self, forKey: .part)
            )

        case "response.reasoning_summary_part.done":
            self = .responseReasoningSummaryPartDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                summaryIndex: try container.decode(Int.self, forKey: .summaryIndex),
                part: try container.decode(XAIResponsesReasoningSummaryPart.self, forKey: .part)
            )

        case "response.reasoning_summary_text.delta":
            self = .responseReasoningSummaryTextDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                summaryIndex: try container.decode(Int.self, forKey: .summaryIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.reasoning_summary_text.done":
            self = .responseReasoningSummaryTextDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                summaryIndex: try container.decode(Int.self, forKey: .summaryIndex),
                text: try container.decode(String.self, forKey: .text)
            )

        case "response.reasoning_text.delta":
            self = .responseReasoningTextDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.reasoning_text.done":
            self = .responseReasoningTextDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                text: try container.decode(String.self, forKey: .text)
            )

        case "response.custom_tool_call_input.delta":
            self = .responseCustomToolCallInputDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.custom_tool_call_input.done":
            self = .responseCustomToolCallInputDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                input: try container.decode(String.self, forKey: .input)
            )

        case "response.function_call_arguments.delta":
            self = .responseFunctionCallArgumentsDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.function_call_arguments.done":
            self = .responseFunctionCallArgumentsDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                arguments: try container.decode(String.self, forKey: .arguments)
            )

        case "response.mcp_call_arguments.delta":
            self = .responseMcpCallArgumentsDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.mcp_call_arguments.done":
            self = .responseMcpCallArgumentsDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                arguments: try container.decodeIfPresent(String.self, forKey: .arguments)
            )

        case "response.mcp_call_output.delta":
            self = .responseMcpCallOutputDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.mcp_call_output.done":
            self = .responseMcpCallOutputDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                output: try container.decodeIfPresent(String.self, forKey: .output)
            )

        case "response.done":
            self = .responseDone(response: try container.decode(XAIResponsesResponse.self, forKey: .response))

        case "response.completed":
            self = .responseCompleted(response: try container.decode(XAIResponsesResponse.self, forKey: .response))

        case "response.web_search_call.in_progress",
             "response.web_search_call.searching",
             "response.web_search_call.completed":
            self = .responseWebSearchCallStatus(
                type: type,
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        case "response.x_search_call.in_progress",
             "response.x_search_call.searching",
             "response.x_search_call.completed":
            self = .responseXSearchCallStatus(
                type: type,
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        case "response.file_search_call.in_progress",
             "response.file_search_call.searching",
             "response.file_search_call.completed":
            self = .responseFileSearchCallStatus(
                type: type,
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        case "response.code_execution_call.in_progress",
             "response.code_execution_call.executing",
             "response.code_execution_call.completed":
            self = .responseCodeExecutionCallStatus(
                type: type,
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        case "response.code_interpreter_call.in_progress",
             "response.code_interpreter_call.executing",
             "response.code_interpreter_call.interpreting",
             "response.code_interpreter_call.completed":
            self = .responseCodeInterpreterCallStatus(
                type: type,
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        case "response.code_interpreter_call_code.delta":
            self = .responseCodeInterpreterCallCodeDelta(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                delta: try container.decode(String.self, forKey: .delta)
            )

        case "response.code_interpreter_call_code.done":
            self = .responseCodeInterpreterCallCodeDone(
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex),
                code: try container.decode(String.self, forKey: .code)
            )

        case "response.mcp_call.in_progress",
             "response.mcp_call.executing",
             "response.mcp_call.completed",
             "response.mcp_call.failed":
            self = .responseMcpCallStatus(
                type: type,
                itemId: try container.decode(String.self, forKey: .itemId),
                outputIndex: try container.decode(Int.self, forKey: .outputIndex)
            )

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown xAI responses chunk type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        func encodeItemId(_ id: String) throws { try container.encode(id, forKey: .itemId) }
        func encodeOutputIndex(_ index: Int) throws { try container.encode(index, forKey: .outputIndex) }

        switch self {
        case .responseCreated(let response):
            try container.encode("response.created", forKey: .type)
            try container.encode(response, forKey: .response)

        case .responseInProgress(let response):
            try container.encode("response.in_progress", forKey: .type)
            try container.encode(response, forKey: .response)

        case .responseOutputItemAdded(let item, let outputIndex):
            try container.encode("response.output_item.added", forKey: .type)
            try container.encode(item, forKey: .item)
            try container.encode(outputIndex, forKey: .outputIndex)

        case .responseOutputItemDone(let item, let outputIndex):
            try container.encode("response.output_item.done", forKey: .type)
            try container.encode(item, forKey: .item)
            try container.encode(outputIndex, forKey: .outputIndex)

        case .responseContentPartAdded(let itemId, let outputIndex, let contentIndex, let part):
            try container.encode("response.content_part.added", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(part, forKey: .part)

        case .responseContentPartDone(let itemId, let outputIndex, let contentIndex, let part):
            try container.encode("response.content_part.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(part, forKey: .part)

        case .responseOutputTextDelta(let itemId, let outputIndex, let contentIndex, let delta):
            try container.encode("response.output_text.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(delta, forKey: .delta)

        case .responseOutputTextDone(let itemId, let outputIndex, let contentIndex, let text, let annotations):
            try container.encode("response.output_text.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(annotations, forKey: .annotations)

        case .responseOutputTextAnnotationAdded(let itemId, let outputIndex, let contentIndex, let annotationIndex, let annotation):
            try container.encode("response.output_text.annotation.added", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(annotationIndex, forKey: .annotationIndex)
            try container.encode(annotation, forKey: .annotation)

        case .responseReasoningSummaryPartAdded(let itemId, let outputIndex, let summaryIndex, let part):
            try container.encode("response.reasoning_summary_part.added", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(summaryIndex, forKey: .summaryIndex)
            try container.encode(part, forKey: .part)

        case .responseReasoningSummaryPartDone(let itemId, let outputIndex, let summaryIndex, let part):
            try container.encode("response.reasoning_summary_part.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(summaryIndex, forKey: .summaryIndex)
            try container.encode(part, forKey: .part)

        case .responseReasoningSummaryTextDelta(let itemId, let outputIndex, let summaryIndex, let delta):
            try container.encode("response.reasoning_summary_text.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(summaryIndex, forKey: .summaryIndex)
            try container.encode(delta, forKey: .delta)

        case .responseReasoningSummaryTextDone(let itemId, let outputIndex, let summaryIndex, let text):
            try container.encode("response.reasoning_summary_text.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(summaryIndex, forKey: .summaryIndex)
            try container.encode(text, forKey: .text)

        case .responseReasoningTextDelta(let itemId, let outputIndex, let contentIndex, let delta):
            try container.encode("response.reasoning_text.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(delta, forKey: .delta)

        case .responseReasoningTextDone(let itemId, let outputIndex, let contentIndex, let text):
            try container.encode("response.reasoning_text.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(text, forKey: .text)

        case .responseCustomToolCallInputDelta(let itemId, let outputIndex, let delta):
            try container.encode("response.custom_tool_call_input.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(delta, forKey: .delta)

        case .responseCustomToolCallInputDone(let itemId, let outputIndex, let input):
            try container.encode("response.custom_tool_call_input.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(input, forKey: .input)

        case .responseFunctionCallArgumentsDelta(let itemId, let outputIndex, let delta):
            try container.encode("response.function_call_arguments.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(delta, forKey: .delta)

        case .responseFunctionCallArgumentsDone(let itemId, let outputIndex, let arguments):
            try container.encode("response.function_call_arguments.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(arguments, forKey: .arguments)

        case .responseMcpCallArgumentsDelta(let itemId, let outputIndex, let delta):
            try container.encode("response.mcp_call_arguments.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(delta, forKey: .delta)

        case .responseMcpCallArgumentsDone(let itemId, let outputIndex, let arguments):
            try container.encode("response.mcp_call_arguments.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encodeIfPresent(arguments, forKey: .arguments)

        case .responseMcpCallOutputDelta(let itemId, let outputIndex, let delta):
            try container.encode("response.mcp_call_output.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(delta, forKey: .delta)

        case .responseMcpCallOutputDone(let itemId, let outputIndex, let output):
            try container.encode("response.mcp_call_output.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encodeIfPresent(output, forKey: .output)

        case .responseDone(let response):
            try container.encode("response.done", forKey: .type)
            try container.encode(response, forKey: .response)

        case .responseCompleted(let response):
            try container.encode("response.completed", forKey: .type)
            try container.encode(response, forKey: .response)

        case .responseWebSearchCallStatus(let type, let itemId, let outputIndex):
            try container.encode(type, forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)

        case .responseXSearchCallStatus(let type, let itemId, let outputIndex):
            try container.encode(type, forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)

        case .responseFileSearchCallStatus(let type, let itemId, let outputIndex):
            try container.encode(type, forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)

        case .responseCodeExecutionCallStatus(let type, let itemId, let outputIndex):
            try container.encode(type, forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)

        case .responseCodeInterpreterCallStatus(let type, let itemId, let outputIndex):
            try container.encode(type, forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)

        case .responseCodeInterpreterCallCodeDelta(let itemId, let outputIndex, let delta):
            try container.encode("response.code_interpreter_call_code.delta", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(delta, forKey: .delta)

        case .responseCodeInterpreterCallCodeDone(let itemId, let outputIndex, let code):
            try container.encode("response.code_interpreter_call_code.done", forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
            try container.encode(code, forKey: .code)

        case .responseMcpCallStatus(let type, let itemId, let outputIndex):
            try container.encode(type, forKey: .type)
            try encodeItemId(itemId)
            try encodeOutputIndex(outputIndex)
        }
    }
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

public let xaiResponsesResponseSchema = FlexibleSchema(
    Schema<XAIResponsesResponse>.codable(
        XAIResponsesResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

public let xaiResponsesChunkSchema = FlexibleSchema(
    Schema<XAIResponsesChunk>.codable(
        XAIResponsesChunk.self,
        jsonSchema: genericJSONObjectSchema
    )
)

extension ParseJSONResult where Output == XAIResponsesChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}
