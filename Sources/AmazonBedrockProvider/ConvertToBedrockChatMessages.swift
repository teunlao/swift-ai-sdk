import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/convert-to-bedrock-chat-messages.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct BedrockChatMessages: Sendable {
    let system: [JSONValue]
    let messages: [JSONValue]
}

private let bedrockCachePointJSON: JSONValue = .object([
    "cachePoint": .object(["type": .string("default")])
])

private let bedrockImageMimeTypes: [String: String] = [
    "image/jpeg": "jpeg",
    "image/png": "png",
    "image/gif": "gif",
    "image/webp": "webp"
]

private let bedrockDocumentMimeTypes: [String: String] = [
    "application/pdf": "pdf",
    "text/csv": "csv",
    "application/msword": "doc",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/vnd.ms-excel": "xls",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
    "text/html": "html",
    "text/plain": "txt",
    "text/markdown": "md"
]

public let bedrockReasoningMetadataSchema = FlexibleSchema(
    Schema<BedrockReasoningMetadata>.codable(
        BedrockReasoningMetadata.self,
        jsonSchema: .object([
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
    )
)

public struct BedrockReasoningMetadata: Codable, Sendable, Equatable {
    public let signature: String?
    public let redactedData: String?
}

func convertToBedrockChatMessages(_ prompt: LanguageModelV3Prompt) async throws -> BedrockChatMessages {
    let blocks = groupIntoBlocks(prompt)
    var system: [JSONValue] = []
    var messages: [JSONValue] = []

    var documentCounter = 0
    func nextDocumentName() -> String {
        documentCounter += 1
        return "document-\(documentCounter)"
    }

    for (blockIndex, block) in blocks.enumerated() {
        let isLastBlock = blockIndex == blocks.count - 1

        switch block {
        case .system(let systemMessages):
            for message in systemMessages {
                system.append(.object(["text": .string(message.content)]))
                if let cachePoint = cachePoint(from: message.providerOptions) {
                    system.append(cachePoint)
                }
            }

        case .user(let entries):
            var content: [JSONValue] = []

            for entry in entries {
                switch entry {
                case .user(let parts, let providerOptions):
                    for part in parts {
                        switch part {
                        case .text(let textPart):
                            content.append(.object(["text": .string(textPart.text)]))
                        case .file(let filePart):
                            if case .url = filePart.data {
                                throw UnsupportedFunctionalityError(functionality: "File URL data")
                            }

                            let base64 = try base64String(from: filePart.data)

                            if filePart.mediaType.lowercased().hasPrefix("image/") {
                                let format = try bedrockImageFormat(for: filePart.mediaType)
                                content.append(
                                    .object([
                                        "image": .object([
                                            "format": .string(format),
                                            "source": .object([
                                                "bytes": .string(base64)
                                            ])
                                        ])
                                    ])
                                )
                            } else {
                                let format = try bedrockDocumentFormat(for: filePart.mediaType)
                                var documentPayload: [String: JSONValue] = [
                                    "format": .string(format),
                                    "name": .string(filePart.filename ?? nextDocumentName()),
                                    "source": .object([
                                        "bytes": .string(base64)
                                    ])
                                ]

                                if try await shouldEnableCitations(providerMetadata: filePart.providerOptions) {
                                    documentPayload["citations"] = .object(["enabled": .bool(true)])
                                }

                                content.append(.object(["document": .object(documentPayload)]))
                            }
                        }
                    }

                    if let cachePoint = cachePoint(from: providerOptions) {
                        content.append(cachePoint)
                    }

                case .tool(let parts, let providerOptions):
                    for part in parts {
                        let converted = try await convertToolResult(part.output)
                        content.append(
                            .object([
                                "toolResult": .object([
                                    "toolUseId": .string(part.toolCallId),
                                    "content": .array(converted)
                                ])
                            ])
                        )
                    }

                    if let cachePoint = cachePoint(from: providerOptions) {
                        content.append(cachePoint)
                    }
                }
            }

            messages.append(.object([
                "role": .string("user"),
                "content": .array(content)
            ]))

        case .assistant(let assistantMessages):
            var content: [JSONValue] = []

            for (messageIndex, message) in assistantMessages.enumerated() {
                let isLastMessage = messageIndex == assistantMessages.count - 1

                for (partIndex, part) in message.parts.enumerated() {
                    let isLastPart = partIndex == message.parts.count - 1

                    switch part {
                    case .text(let textPart):
                        let trimmed = trimIfNeeded(textPart.text, isLastBlock: isLastBlock, isLastMessage: isLastMessage, isLastPart: isLastPart)
                        if !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            content.append(.object(["text": .string(trimmed)]))
                        }

                    case .file:
                        throw UnsupportedFunctionalityError(functionality: "Assistant file content")

                    case .reasoning(let reasoningPart):
                        let trimmed = trimIfNeeded(reasoningPart.text, isLastBlock: isLastBlock, isLastMessage: isLastMessage, isLastPart: isLastPart)
                        if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            continue
                        }

                        let metadata = try await parseReasoningMetadata(reasoningPart.providerOptions)
                        if let metadata {
                            if let signature = metadata.signature {
                                content.append(
                                    .object([
                                        "reasoningContent": .object([
                                            "reasoningText": .object([
                                                "text": .string(trimmed),
                                                "signature": .string(signature)
                                            ])
                                        ])
                                    ])
                                )
                            } else if let redacted = metadata.redactedData {
                                content.append(
                                    .object([
                                        "reasoningContent": .object([
                                            "redactedReasoning": .object([
                                                "data": .string(redacted)
                                            ])
                                        ])
                                    ])
                                )
                            } else {
                                content.append(.object([
                                    "reasoningContent": .object([
                                        "reasoningText": .object([
                                            "text": .string(trimmed)
                                        ])
                                    ])
                                ]))
                            }
                        } else {
                            content.append(.object([
                                "reasoningContent": .object([
                                    "reasoningText": .object([
                                        "text": .string(trimmed)
                                    ])
                                ])
                            ]))
                        }

                    case .toolCall(let toolCallPart):
                        let inputText = try canonicalJSONString(from: toolCallPart.input)
                        content.append(.object([
                            "toolUse": .object([
                                "toolUseId": .string(toolCallPart.toolCallId),
                                "name": .string(toolCallPart.toolName),
                                "input": .string(inputText)
                            ])
                        ]))

                    case .toolResult:
                        throw UnsupportedFunctionalityError(functionality: "Assistant tool-result content")
                    }
                }

                if let cachePoint = cachePoint(from: message.providerOptions) {
                    content.append(cachePoint)
                }
            }

            messages.append(.object([
                "role": .string("assistant"),
                "content": .array(content)
            ]))
        }
    }

    return BedrockChatMessages(system: system, messages: messages)
}

// MARK: - Tool Result Conversion

private func convertToolResult(_ output: LanguageModelV3ToolResultOutput) async throws -> [JSONValue] {
    switch output {
    case .content(let parts):
        return try parts.map { part in
            switch part {
            case .text(let text):
                return .object(["text": .string(text)])
            case .media(let data, let mediaType):
                guard mediaType.lowercased().hasPrefix("image/") else {
                    throw UnsupportedFunctionalityError(functionality: "media type: \(mediaType)")
                }
                let format = try bedrockImageFormat(for: mediaType)
                return .object([
                    "image": .object([
                        "format": .string(format),
                        "source": .object([
                            "bytes": .string(data)
                        ])
                    ])
                ])
            }
        }
    case .text(let text):
        return [.object(["text": .string(text)])]
    case .errorText(let text):
        return [.object(["text": .string(text)])]
    case .executionDenied(let reason):
        return [.object(["text": .string(reason ?? "Tool execution denied.")])]
    case .json(let json), .errorJson(let json):
        let jsonText = try canonicalJSONString(from: json)
        return [.object(["text": .string(jsonText)])]
    }
}

// MARK: - Helpers

private func base64String(from dataContent: LanguageModelV3DataContent) throws -> String {
    switch dataContent {
    case .data(let data):
        return convertDataToBase64(data)
    case .base64(let string):
        return string
    case .url:
        throw UnsupportedFunctionalityError(functionality: "File URL data")
    }
}

private func bedrockImageFormat(for mediaType: String) throws -> String {
    guard let format = bedrockImageMimeTypes[mediaType.lowercased()] else {
        throw UnsupportedFunctionalityError(
            functionality: "image mime type: \(mediaType)",
            message: "Unsupported image mime type: \(mediaType), expected one of: \(bedrockImageMimeTypes.keys.sorted().joined(separator: ", "))"
        )
    }
    return format
}

private func bedrockDocumentFormat(for mediaType: String) throws -> String {
    guard let format = bedrockDocumentMimeTypes[mediaType.lowercased()] else {
        throw UnsupportedFunctionalityError(
            functionality: "file mime type: \(mediaType)",
            message: "Unsupported file mime type: \(mediaType), expected one of: \(bedrockDocumentMimeTypes.keys.sorted().joined(separator: ", "))"
        )
    }
    return format
}

private func trimIfNeeded(_ text: String, isLastBlock: Bool, isLastMessage: Bool, isLastPart: Bool) -> String {
    if isLastBlock && isLastMessage && isLastPart {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
}

private func cachePoint(from providerOptions: SharedV3ProviderOptions?) -> JSONValue? {
    guard let value = providerOptions?["bedrock"]?["cachePoint"], value != .null else {
        return nil
    }
    return bedrockCachePointJSON
}

private func shouldEnableCitations(providerMetadata: SharedV3ProviderOptions?) async throws -> Bool {
    guard let providerMetadata else { return false }
    let parsed = try await parseProviderOptions(
        provider: "bedrock",
        providerOptions: providerMetadata,
        schema: bedrockFilePartProviderOptionsSchema
    )
    return parsed?.citations?.enabled ?? false
}

private func parseReasoningMetadata(_ providerOptions: SharedV3ProviderOptions?) async throws -> BedrockReasoningMetadata? {
    guard let providerOptions else { return nil }
    return try await parseProviderOptions(
        provider: "bedrock",
        providerOptions: providerOptions,
        schema: bedrockReasoningMetadataSchema
    )
}

private func canonicalJSONString(from value: JSONValue) throws -> String {
    let foundation = jsonValueToFoundation(value)
    return try canonicalJSONString(any: foundation)
}

private func canonicalJSONString(any value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [])
    guard let string = String(data: data, encoding: .utf8) else {
        let context = EncodingError.Context(codingPath: [], debugDescription: "Unable to encode JSON value to UTF-8 string.")
        throw JSONParseError(text: "<json>", cause: EncodingError.invalidValue(value, context))
    }
    return string
}

// MARK: - Block Grouping

private enum BedrockPromptBlock {
    case system([SystemMessage])
    case user([UserEntry])
    case assistant([AssistantMessage])
}

private struct SystemMessage: Sendable {
    let content: String
    let providerOptions: SharedV3ProviderOptions?
}

private enum UserEntry: Sendable {
    case user(parts: [LanguageModelV3UserMessagePart], providerOptions: SharedV3ProviderOptions?)
    case tool(parts: [LanguageModelV3ToolResultPart], providerOptions: SharedV3ProviderOptions?)
}

private struct AssistantMessage: Sendable {
    let parts: [LanguageModelV3MessagePart]
    let providerOptions: SharedV3ProviderOptions?
}

private func groupIntoBlocks(_ prompt: LanguageModelV3Prompt) -> [BedrockPromptBlock] {
    var blocks: [BedrockPromptBlock] = []
    var systemBuffer: [SystemMessage] = []
    var assistantBuffer: [AssistantMessage] = []
    var userBuffer: [UserEntry] = []

    func flushSystem() {
        if !systemBuffer.isEmpty {
            blocks.append(.system(systemBuffer))
            systemBuffer.removeAll()
        }
    }

    func flushAssistant() {
        if !assistantBuffer.isEmpty {
            blocks.append(.assistant(assistantBuffer))
            assistantBuffer.removeAll()
        }
    }

    func flushUser() {
        if !userBuffer.isEmpty {
            blocks.append(.user(userBuffer))
            userBuffer.removeAll()
        }
    }

    for message in prompt {
        switch message {
        case .system(let content, let providerOptions):
            flushAssistant()
            flushUser()
            systemBuffer.append(SystemMessage(content: content, providerOptions: providerOptions))
        case .assistant(let parts, let providerOptions):
            flushSystem()
            flushUser()
            assistantBuffer.append(AssistantMessage(parts: parts, providerOptions: providerOptions))
        case .user(let parts, let providerOptions):
            flushSystem()
            flushAssistant()
            userBuffer.append(.user(parts: parts, providerOptions: providerOptions))
        case .tool(let parts, let providerOptions):
            flushSystem()
            flushAssistant()
            userBuffer.append(.tool(parts: parts, providerOptions: providerOptions))
        }
    }

    flushSystem()
    flushAssistant()
    flushUser()

    return blocks
}
