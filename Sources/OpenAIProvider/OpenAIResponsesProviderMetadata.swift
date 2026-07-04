import AISDKProvider

public struct OpenAIResponsesProviderMetadataPayload: Sendable, Equatable {
    public var responseId: String?
    public var logprobs: [JSONValue]?
    public var serviceTier: String?

    public init(responseId: String? = nil, logprobs: [JSONValue]? = nil, serviceTier: String? = nil) {
        self.responseId = responseId
        self.logprobs = logprobs
        self.serviceTier = serviceTier
    }
}

public struct OpenaiResponsesProviderMetadata: Sendable, Equatable {
    public var openai: OpenAIResponsesProviderMetadataPayload

    public init(openai: OpenAIResponsesProviderMetadataPayload) {
        self.openai = openai
    }
}

public struct OpenAIResponsesReasoningProviderMetadataPayload: Sendable, Equatable {
    public var itemId: String
    public var reasoningEncryptedContent: String?

    public init(itemId: String, reasoningEncryptedContent: String? = nil) {
        self.itemId = itemId
        self.reasoningEncryptedContent = reasoningEncryptedContent
    }
}

public struct OpenaiResponsesReasoningProviderMetadata: Sendable, Equatable {
    public var openai: OpenAIResponsesReasoningProviderMetadataPayload

    public init(openai: OpenAIResponsesReasoningProviderMetadataPayload) {
        self.openai = openai
    }
}

public struct OpenAIResponsesCompactionProviderMetadataPayload: Sendable, Equatable {
    public let type: String
    public var itemId: String
    public var encryptedContent: String?

    public init(itemId: String, encryptedContent: String? = nil) {
        self.type = "compaction"
        self.itemId = itemId
        self.encryptedContent = encryptedContent
    }
}

public struct OpenaiResponsesCompactionProviderMetadata: Sendable, Equatable {
    public var openai: OpenAIResponsesCompactionProviderMetadataPayload

    public init(openai: OpenAIResponsesCompactionProviderMetadataPayload) {
        self.openai = openai
    }
}

public enum OpenAIResponsesTextPhase: String, Sendable, Equatable {
    case commentary
    case finalAnswer = "final_answer"
}

public struct OpenAIResponsesTextProviderMetadataPayload: Sendable, Equatable {
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
    public var openai: OpenAIResponsesTextProviderMetadataPayload

    public init(openai: OpenAIResponsesTextProviderMetadataPayload) {
        self.openai = openai
    }
}

public enum OpenAIResponsesSourceDocumentProviderMetadataPayload: Sendable, Equatable {
    case fileCitation(fileId: String, index: Int)
    case containerFileCitation(fileId: String, containerId: String)
    case filePath(fileId: String, index: Int)

    public var type: String {
        switch self {
        case .fileCitation:
            return "file_citation"
        case .containerFileCitation:
            return "container_file_citation"
        case .filePath:
            return "file_path"
        }
    }
}

public struct OpenaiResponsesSourceDocumentProviderMetadata: Sendable, Equatable {
    public var openai: OpenAIResponsesSourceDocumentProviderMetadataPayload

    public init(openai: OpenAIResponsesSourceDocumentProviderMetadataPayload) {
        self.openai = openai
    }
}
