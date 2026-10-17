import AISDKProvider

public struct ResponsesProviderMetadata: Sendable, Equatable, Decodable {
    public var responseId: String?
    public var logprobs: [JSONValue]?
    public var serviceTier: String?
    public var reasoningContext: String?

    public init(responseId: String? = nil, logprobs: [JSONValue]? = nil, serviceTier: String? = nil, reasoningContext: String? = nil) {
        self.responseId = responseId
        self.logprobs = logprobs
        self.serviceTier = serviceTier
        self.reasoningContext = reasoningContext
    }
}

public struct OpenaiResponsesProviderMetadata: Sendable, Equatable, Decodable {
    public var openai: ResponsesProviderMetadata
    public init(openai: ResponsesProviderMetadata) { self.openai = openai }
}

public struct ResponsesReasoningProviderMetadata: Sendable, Equatable, Decodable {
    public var itemId: String
    public var reasoningEncryptedContent: String?

    public init(itemId: String, reasoningEncryptedContent: String? = nil) {
        self.itemId = itemId
        self.reasoningEncryptedContent = reasoningEncryptedContent
    }
}

public struct OpenaiResponsesReasoningProviderMetadata: Sendable, Equatable, Decodable {
    public var openai: ResponsesReasoningProviderMetadata
    public init(openai: ResponsesReasoningProviderMetadata) { self.openai = openai }
}

public struct ResponsesToolCallProviderMetadata: Sendable, Equatable {
    public enum Caller: Sendable, Equatable {
        case direct
        case program(callerId: String)
    }

    public var itemId: String
    public var async: Bool?
    public var namespace: String?
    public var caller: Caller?

    public init(itemId: String, async: Bool? = nil, namespace: String? = nil, caller: Caller? = nil) {
        self.itemId = itemId
        self.async = async
        self.namespace = namespace
        self.caller = caller
    }
}

public struct OpenaiResponsesToolCallProviderMetadata: Sendable, Equatable {
    public var openai: ResponsesToolCallProviderMetadata
    public init(openai: ResponsesToolCallProviderMetadata) { self.openai = openai }
}

public struct ResponsesCompactionProviderMetadata: Sendable, Equatable {
    public let type = "compaction"
    public var itemId: String
    public var encryptedContent: String?

    public init(itemId: String, encryptedContent: String? = nil) {
        self.itemId = itemId
        self.encryptedContent = encryptedContent
    }
}

public struct OpenaiResponsesCompactionProviderMetadata: Sendable, Equatable {
    public var openai: ResponsesCompactionProviderMetadata
    public init(openai: ResponsesCompactionProviderMetadata) { self.openai = openai }
}

public enum OpenAIResponsesTextPhase: String, Sendable, Equatable, Decodable {
    case commentary
    case finalAnswer = "final_answer"
}

public struct ResponsesTextProviderMetadata: Sendable, Equatable, Decodable {
    public var itemId: String
    public var phase: OpenAIResponsesTextPhase?
    public var annotations: [JSONValue]?

    public init(itemId: String, phase: OpenAIResponsesTextPhase? = nil, annotations: [JSONValue]? = nil) {
        self.itemId = itemId
        self.phase = phase
        self.annotations = annotations
    }
}

public struct OpenaiResponsesTextProviderMetadata: Sendable, Equatable, Decodable {
    public var openai: ResponsesTextProviderMetadata
    public init(openai: ResponsesTextProviderMetadata) { self.openai = openai }
}

public enum ResponsesSourceDocumentProviderMetadata: Sendable, Equatable, Decodable {
    case fileSearch(fileId: String)
    case fileCitation(fileId: String, index: Double)
    case containerFileCitation(fileId: String, containerId: String)
    case filePath(fileId: String, index: Double)

    private enum Keys: String, CodingKey { case type, fileId, index, containerId }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        switch try fields.decode(String.self, forKey: .type) {
        case "file_search": self = .fileSearch(fileId: try fields.decode(String.self, forKey: .fileId))
        case "file_citation": self = .fileCitation(fileId: try fields.decode(String.self, forKey: .fileId), index: try fields.decode(Double.self, forKey: .index))
        case "container_file_citation": self = .containerFileCitation(fileId: try fields.decode(String.self, forKey: .fileId), containerId: try fields.decode(String.self, forKey: .containerId))
        case "file_path": self = .filePath(fileId: try fields.decode(String.self, forKey: .fileId), index: try fields.decode(Double.self, forKey: .index))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: fields, debugDescription: "Unknown Responses document source")
        }
    }

    public var type: String {
        switch self {
        case .fileSearch: return "file_search"
        case .fileCitation: return "file_citation"
        case .containerFileCitation: return "container_file_citation"
        case .filePath: return "file_path"
        }
    }
}

public struct OpenaiResponsesSourceDocumentProviderMetadata: Sendable, Equatable, Decodable {
    public var openai: ResponsesSourceDocumentProviderMetadata
    public init(openai: ResponsesSourceDocumentProviderMetadata) { self.openai = openai }
}
