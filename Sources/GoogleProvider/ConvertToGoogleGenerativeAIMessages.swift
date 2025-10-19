import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleGenerativeAIMessagesOptions: Sendable, Equatable {
    public var isGemmaModel: Bool

    public init(isGemmaModel: Bool = false) {
        self.isGemmaModel = isGemmaModel
    }
}

func convertToGoogleGenerativeAIMessages(
    _ prompt: LanguageModelV3Prompt,
    options: GoogleGenerativeAIMessagesOptions = GoogleGenerativeAIMessagesOptions()
) throws -> GoogleGenerativeAIPrompt {
    var systemInstructionParts: [GoogleGenerativeAISystemInstructionPart] = []
    var contents: [GoogleGenerativeAIContent] = []
    var systemMessagesAllowed = true
    let isGemmaModel = options.isGemmaModel

    for message in prompt {
        switch message {
        case .system(let content, _):
            if !systemMessagesAllowed {
                throw UnsupportedFunctionalityError(functionality: "system messages are only supported at the beginning of the conversation")
            }
            systemInstructionParts.append(.init(text: content))

        case .user(let parts, _):
            systemMessagesAllowed = false

            var converted: [GoogleGenerativeAIContentPart] = []
            for part in parts {
                switch part {
                case .text(let textPart):
                    converted.append(.text(.init(text: textPart.text)))

                case .file(let filePart):
                    let mediaType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType

                    switch filePart.data {
                    case .url(let url):
                        converted.append(.fileData(.init(mimeType: mediaType, fileURI: url.absoluteString)))
                    case .data(let data):
                        converted.append(.inlineData(.init(
                            mimeType: mediaType,
                            data: convertToBase64(.data(data))
                        )))
                    case .base64(let base64):
                        converted.append(.inlineData(.init(
                            mimeType: mediaType,
                            data: convertToBase64(.string(base64))
                        )))
                    }
                }
            }

            contents.append(.init(role: .user, parts: converted))

        case .assistant(let parts, let providerOptions):
            systemMessagesAllowed = false

            let converted = try parts.compactMap { part -> GoogleGenerativeAIContentPart? in
                switch part {
                case .text(let textPart):
                    guard !textPart.text.isEmpty else { return nil }
                    return .text(
                        .init(
                            text: textPart.text,
                            thoughtSignature: googleThoughtSignature(from: textPart.providerOptions ?? providerOptions)
                        )
                    )

                case .reasoning(let reasoningPart):
                    guard !reasoningPart.text.isEmpty else { return nil }
                    return .text(
                        .init(
                            text: reasoningPart.text,
                            thought: true,
                            thoughtSignature: googleThoughtSignature(from: reasoningPart.providerOptions ?? providerOptions)
                        )
                    )

                case .file(let filePart):
                    guard filePart.mediaType == "image/png" else {
                        throw UnsupportedFunctionalityError(functionality: "Only PNG images are supported in assistant messages")
                    }

                    guard case let .data(data) = filePart.data else {
                        throw UnsupportedFunctionalityError(functionality: "File data URLs in assistant messages are not supported")
                    }

                    return .inlineData(.init(
                        mimeType: filePart.mediaType,
                        data: convertToBase64(.data(data))
                    ))

                case .toolCall(let toolCall):
                    return .functionCall(
                        .init(
                            name: toolCall.toolName,
                            arguments: toolCall.input,
                            thoughtSignature: googleThoughtSignature(from: toolCall.providerOptions ?? providerOptions)
                        )
                    )

                case .toolResult:
                    // Tool results in assistant role are ignored, they should arrive as tool messages.
                    return nil
                }
            }

            contents.append(.init(role: .model, parts: converted))

        case .tool(let parts, _):
            systemMessagesAllowed = false

            var converted: [GoogleGenerativeAIContentPart] = []

            for part in parts {
                switch part.output {
                case .content(let value):
                    for contentPart in value {
                        switch contentPart {
                        case .text(let text):
                            let response = JSONValue.object([
                                "name": .string(part.toolName),
                                "content": .string(text)
                            ])
                            converted.append(.functionResponse(.init(name: part.toolName, response: response)))
                        case .media(let data, let mediaType):
                            converted.append(.inlineData(.init(mimeType: mediaType, data: data)))
                            converted.append(.text(.init(text: "Tool executed successfully and returned this image as a response")))
                        }
                    }

                case .text(let value):
                    let response = JSONValue.object([
                        "name": .string(part.toolName),
                        "content": .string(value)
                    ])
                    converted.append(.functionResponse(.init(name: part.toolName, response: response)))

                case .json(let value):
                    let response = JSONValue.object([
                        "name": .string(part.toolName),
                        "content": value
                    ])
                    converted.append(.functionResponse(.init(name: part.toolName, response: response)))

                case .executionDenied(let reason):
                    let response = JSONValue.object([
                        "name": .string(part.toolName),
                        "content": .string(reason ?? "Tool execution denied.")
                    ])
                    converted.append(.functionResponse(.init(name: part.toolName, response: response)))

                case .errorText(let value):
                    let response = JSONValue.object([
                        "name": .string(part.toolName),
                        "content": .string(value)
                    ])
                    converted.append(.functionResponse(.init(name: part.toolName, response: response)))

                case .errorJson(let value):
                    let response = JSONValue.object([
                        "name": .string(part.toolName),
                        "content": value
                    ])
                    converted.append(.functionResponse(.init(name: part.toolName, response: response)))
                }
            }

            contents.append(.init(role: .user, parts: converted))
        }
    }

    if isGemmaModel,
       !systemInstructionParts.isEmpty,
       !contents.isEmpty,
       contents.first?.role == .user {
        let systemText = systemInstructionParts.map { $0.text }.joined(separator: "\n\n")
        var first = contents[0]
        first.parts.insert(.text(.init(text: systemText + "\n\n")), at: 0)
        contents[0] = first
        systemInstructionParts.removeAll()
    }

    let systemInstruction = systemInstructionParts.isEmpty || isGemmaModel
        ? nil
        : GoogleGenerativeAISystemInstruction(parts: systemInstructionParts)

    return GoogleGenerativeAIPrompt(
        systemInstruction: systemInstruction,
        contents: contents
    )
}

private func googleThoughtSignature(from providerOptions: SharedV3ProviderOptions?) -> String? {
    guard let options = providerOptions?["google"],
          let value = options["thoughtSignature"],
          case .string(let signature) = value else {
        return nil
    }
    return signature
}
