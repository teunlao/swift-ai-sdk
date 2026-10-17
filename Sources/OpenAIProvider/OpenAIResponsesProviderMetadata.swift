import AISDKProvider

public struct ResponsesProviderMetadata: Sendable, Equatable {
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

public struct OpenaiResponsesProviderMetadata: Sendable, Equatable {
    public var openai: ResponsesProviderMetadata
    public init(openai: ResponsesProviderMetadata) { self.openai = openai }
}

public struct ResponsesReasoningProviderMetadata: Sendable, Equatable {
    public var itemId: String
    public var reasoningEncryptedContent: String?

    public init(itemId: String, reasoningEncryptedContent: String? = nil) {
        self.itemId = itemId
        self.reasoningEncryptedContent = reasoningEncryptedContent
    }
}

public struct OpenaiResponsesReasoningProviderMetadata: Sendable, Equatable {
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

public enum OpenAIResponsesTextPhase: String, Sendable, Equatable {
    case commentary
    case finalAnswer = "final_answer"
}

public struct ResponsesTextProviderMetadata: Sendable, Equatable {
    public var itemId: String
    public var phase: OpenAIResponsesTextPhase?
    public var annotations: [JSONValue]?

    public init(itemId: String, phase: OpenAIResponsesTextPhase? = nil, annotations: [JSONValue]? = nil) {
        self.itemId = itemId
        self.phase = phase
        self.annotations = annotations
    }
}

public struct OpenaiResponsesTextProviderMetadata: Sendable, Equatable {
    public var openai: ResponsesTextProviderMetadata
    public init(openai: ResponsesTextProviderMetadata) { self.openai = openai }
}

public enum ResponsesSourceDocumentProviderMetadata: Sendable, Equatable {
    case fileSearch(fileId: String)
    case fileCitation(fileId: String, index: Double)
    case containerFileCitation(fileId: String, containerId: String)
    case filePath(fileId: String, index: Double)

    public var type: String {
        switch self {
        case .fileSearch: return "file_search"
        case .fileCitation: return "file_citation"
        case .containerFileCitation: return "container_file_citation"
        case .filePath: return "file_path"
        }
    }
}

public struct OpenaiResponsesSourceDocumentProviderMetadata: Sendable, Equatable {
    public var openai: ResponsesSourceDocumentProviderMetadata
    public init(openai: ResponsesSourceDocumentProviderMetadata) { self.openai = openai }
}
