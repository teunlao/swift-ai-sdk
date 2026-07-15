import Foundation
import AISDKProvider
import AISDKProviderUtils

typealias OpenAIResponsesPrompt = [OpenAIResponsesPromptMessage]

enum OpenAIResponsesPromptMessage {
    case system(content: String, providerOptions: SharedV3ProviderOptions?)
    case user(content: [LanguageModelV3UserMessagePart], providerOptions: SharedV3ProviderOptions?)
    case assistant(content: [OpenAIResponsesAssistantMessagePart], providerOptions: SharedV3ProviderOptions?)
    case tool(content: [OpenAIResponsesToolMessagePart], providerOptions: SharedV3ProviderOptions?)
}

enum OpenAIResponsesAssistantMessagePart {
    case text(LanguageModelV3TextPart)
    case toolCall(LanguageModelV3ToolCallPart)
    case toolResult(OpenAIResponsesToolResultPart)
    case reasoning(LanguageModelV3ReasoningPart)
    case custom(LanguageModelV3CustomPart)
    case file(LanguageModelV3FilePart)
}

enum OpenAIResponsesToolMessagePart {
    case toolResult(OpenAIResponsesToolResultPart)
    case toolApprovalResponse(LanguageModelV3ToolApprovalResponsePart)
}

struct OpenAIResponsesToolResultPart {
    let toolCallId: String
    let toolName: String
    let output: OpenAIResponsesToolResultOutput
    let providerMetadata: SharedV3ProviderMetadata?
    let providerOptions: SharedV3ProviderOptions?
}

enum OpenAIResponsesToolResultOutput {
    case text(value: String, providerOptions: SharedV3ProviderOptions?)
    case json(value: JSONValue, providerOptions: SharedV3ProviderOptions?)
    case executionDenied(reason: String?, providerOptions: SharedV3ProviderOptions?)
    case errorText(value: String, providerOptions: SharedV3ProviderOptions?)
    case errorJson(value: JSONValue, providerOptions: SharedV3ProviderOptions?)
    case content(value: [OpenAIResponsesToolResultContentPart], providerOptions: SharedV3ProviderOptions?)
}

enum OpenAIResponsesToolResultContentPart {
    case text(text: String, providerOptions: SharedV3ProviderOptions?)
    case file(
        data: OpenAIResponsesToolResultFileData,
        mediaType: String,
        filename: String?,
        providerOptions: SharedV3ProviderOptions?
    )
    case custom(providerOptions: SharedV3ProviderOptions?)
}

enum OpenAIResponsesToolResultFileData {
    case data(Data)
    case base64(String)
    case url(URL)
    case reference(SharedV4ProviderReference)
    case text(String)
}

extension Array where Element == OpenAIResponsesPromptMessage {
    init(v3 prompt: LanguageModelV3Prompt) {
        self = prompt.map { message in
            switch message {
            case let .system(content, providerOptions):
                return .system(content: content, providerOptions: providerOptions)
            case let .user(content, providerOptions):
                return .user(content: content, providerOptions: providerOptions)
            case let .assistant(content, providerOptions):
                return .assistant(
                    content: content.map(OpenAIResponsesAssistantMessagePart.init),
                    providerOptions: providerOptions
                )
            case let .tool(content, providerOptions):
                return .tool(
                    content: content.map(OpenAIResponsesToolMessagePart.init),
                    providerOptions: providerOptions
                )
            }
        }
    }

    init(v4 prompt: LanguageModelV4Prompt, providerOptionsName: String) throws {
        self = try prompt.map { message in
            switch message {
            case let .system(content, providerOptions):
                return .system(content: content, providerOptions: providerOptions)
            case let .user(content, providerOptions):
                return .user(
                    content: try content.map {
                        try convertOpenAIResponsesV4UserMessagePartToV3(
                            $0,
                            providerOptionsName: providerOptionsName
                        )
                    },
                    providerOptions: providerOptions
                )
            case let .assistant(content, providerOptions):
                return .assistant(
                    content: try content.compactMap {
                        try OpenAIResponsesAssistantMessagePart(
                            v4: $0,
                            providerOptionsName: providerOptionsName
                        )
                    },
                    providerOptions: providerOptions
                )
            case let .tool(content, providerOptions):
                return .tool(
                    content: try content.map {
                        try OpenAIResponsesToolMessagePart(
                            v4: $0,
                            providerOptionsName: providerOptionsName
                        )
                    },
                    providerOptions: providerOptions
                )
            }
        }
    }
}

private extension OpenAIResponsesAssistantMessagePart {
    init(_ value: LanguageModelV3MessagePart) {
        switch value {
        case .text(let part): self = .text(part)
        case .toolCall(let part): self = .toolCall(part)
        case .toolResult(let part): self = .toolResult(.init(part))
        case .reasoning(let part): self = .reasoning(part)
        case .custom(let part): self = .custom(part)
        case .file(let part): self = .file(part)
        }
    }

    init?(v4 value: LanguageModelV4MessagePart, providerOptionsName: String) throws {
        switch value {
        case .text(let part):
            self = .text(.init(text: part.text, providerOptions: part.providerOptions))
        case .file(let part):
            self = .file(.init(
                data: try convertOpenAIResponsesV4FileDataToV3(part.data, providerOptionsName: providerOptionsName),
                mediaType: part.mediaType,
                filename: part.filename,
                providerOptions: part.providerOptions
            ))
        case .reasoning(let part):
            self = .reasoning(.init(text: part.text, providerOptions: part.providerOptions))
        case .toolCall(let part):
            self = .toolCall(.init(
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                input: part.input,
                providerExecuted: part.providerExecuted,
                providerOptions: part.providerOptions
            ))
        case .toolResult(let part):
            self = .toolResult(.init(v4: part, providerOptionsName: providerOptionsName))
        case .custom(let part):
            guard part.kind == "openai.compaction" else {
                throw UnsupportedFunctionalityError(
                    functionality: "language model v4 custom prompt part kind \(part.kind) on OpenAI Responses"
                )
            }
            self = .custom(.init(kind: part.kind, providerOptions: part.providerOptions))
        case .reasoningFile:
            throw UnsupportedFunctionalityError(
                functionality: "language model v4 reasoning-file prompt parts on OpenAI Responses"
            )
        }
    }
}

private extension OpenAIResponsesToolMessagePart {
    init(_ value: LanguageModelV3ToolMessagePart) {
        switch value {
        case .toolResult(let part): self = .toolResult(.init(part))
        case .toolApprovalResponse(let part): self = .toolApprovalResponse(part)
        }
    }

    init(v4 value: LanguageModelV4ToolMessagePart, providerOptionsName: String) throws {
        switch value {
        case .toolResult(let part):
            self = .toolResult(.init(v4: part, providerOptionsName: providerOptionsName))
        case .toolApprovalResponse(let part):
            self = .toolApprovalResponse(.init(
                approvalId: part.approvalId,
                approved: part.approved,
                reason: part.reason,
                providerOptions: part.providerOptions
            ))
        }
    }
}

private extension OpenAIResponsesToolResultPart {
    init(_ value: LanguageModelV3ToolResultPart) {
        self.init(
            toolCallId: value.toolCallId,
            toolName: value.toolName,
            output: .init(value.output),
            providerMetadata: value.providerMetadata,
            providerOptions: value.providerOptions
        )
    }

    init(v4 value: LanguageModelV4ToolResultPart, providerOptionsName: String) {
        self.init(
            toolCallId: value.toolCallId,
            toolName: value.toolName,
            output: .init(v4: value.output, providerOptionsName: providerOptionsName),
            providerMetadata: nil,
            providerOptions: value.providerOptions
        )
    }
}

private extension OpenAIResponsesToolResultOutput {
    init(_ value: LanguageModelV3ToolResultOutput) {
        switch value {
        case let .text(value, options): self = .text(value: value, providerOptions: options)
        case let .json(value, options): self = .json(value: value, providerOptions: options)
        case let .executionDenied(reason, options): self = .executionDenied(reason: reason, providerOptions: options)
        case let .errorText(value, options): self = .errorText(value: value, providerOptions: options)
        case let .errorJson(value, options): self = .errorJson(value: value, providerOptions: options)
        case let .content(value, options):
            self = .content(
                value: value.map(OpenAIResponsesToolResultContentPart.init),
                providerOptions: options
            )
        }
    }

    init(v4 value: LanguageModelV4ToolResultOutput, providerOptionsName: String) {
        switch value {
        case let .text(value, options): self = .text(value: value, providerOptions: options)
        case let .json(value, options): self = .json(value: value, providerOptions: options)
        case let .executionDenied(reason, options): self = .executionDenied(reason: reason, providerOptions: options)
        case let .errorText(value, options): self = .errorText(value: value, providerOptions: options)
        case let .errorJson(value, options): self = .errorJson(value: value, providerOptions: options)
        case .content(let value):
            self = .content(
                value: value.map { .init(v4: $0, providerOptionsName: providerOptionsName) },
                providerOptions: nil
            )
        }
    }
}

private extension OpenAIResponsesToolResultContentPart {
    init(_ value: LanguageModelV3ToolResultContentPart) {
        switch value {
        case .text(let text):
            self = .text(text: text, providerOptions: nil)
        case let .media(data, mediaType):
            self = .file(data: .base64(data), mediaType: mediaType, filename: nil, providerOptions: nil)
        }
    }

    init(v4 value: LanguageModelV4ToolResultContentPart, providerOptionsName: String) {
        switch value {
        case let .text(text, options):
            self = .text(text: text, providerOptions: options)
        case let .file(data, mediaType, filename, options):
            self = .file(
                data: .init(v4: data, providerOptionsName: providerOptionsName),
                mediaType: mediaType,
                filename: filename,
                providerOptions: options
            )
        case .custom(let options):
            self = .custom(providerOptions: options)
        }
    }
}

private extension OpenAIResponsesToolResultFileData {
    init(v4 value: SharedV4FileData, providerOptionsName: String) {
        switch value {
        case .data(let data): self = .data(data)
        case .base64(let base64): self = .base64(base64)
        case .url(let url): self = .url(url)
        case .text(let text): self = .text(text)
        case .reference(let reference):
            self = .reference(reference)
        }
    }
}
