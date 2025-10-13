import Foundation

/**
 Converts prompt messages to LanguageModelV3 format for provider consumption.

 Port of `@ai-sdk/ai/src/prompt/convert-to-language-model-prompt.ts`.

 This module handles:
 - Converting ModelMessage types to LanguageModelV3Message format
 - Downloading assets from URLs when models don't support URL references
 - Converting content parts (text, images, files, reasoning, tool calls)
 - Combining consecutive tool messages for efficiency
 */

/**
 Converts a standardized prompt to LanguageModelV3 format.

 - Parameter prompt: The standardized prompt to convert
 - Parameter supportedUrls: Map of media types to supported URL patterns
 - Parameter download: Download function for fetching URL assets (optional)
 - Returns: Array of LanguageModelV3Message suitable for provider consumption
 - Throws: Various errors during conversion or download
 */
public func convertToLanguageModelPrompt(
    prompt: StandardizedPrompt,
    supportedUrls: [String: [NSRegularExpression]],
    download: DownloadFunction? = nil
) async throws -> LanguageModelV3Prompt {
    // Download assets from URLs if needed
    let downloadedAssets = try await downloadAssets(
        messages: prompt.messages,
        download: download ?? createDefaultDownloadFunction(),
        supportedUrls: supportedUrls
    )

    // Convert system message if present
    var messages: [LanguageModelV3Message] = []
    if let system = prompt.system {
        messages.append(.system(content: system, providerOptions: nil))
    }

    // Convert all user/assistant/tool messages
    messages.append(contentsOf: try prompt.messages.map { message in
        try convertToLanguageModelMessage(message: message, downloadedAssets: downloadedAssets)
    })

    // Combine consecutive tool messages into a single tool message
    var combinedMessages: [LanguageModelV3Message] = []
    for message in messages {
        // Extract role and content
        switch message {
        case .tool(let content, let providerOptions):
            // Check if last message is also a tool message
            if case .tool(var lastContent, _) = combinedMessages.last {
                // Merge content arrays
                combinedMessages.removeLast()
                lastContent.append(contentsOf: content)
                combinedMessages.append(.tool(content: lastContent, providerOptions: providerOptions))
            } else {
                combinedMessages.append(message)
            }
        default:
            combinedMessages.append(message)
        }
    }

    return combinedMessages
}

/**
 Converts a ModelMessage to a LanguageModelV3Message.

 - Parameter message: The ModelMessage to convert
 - Parameter downloadedAssets: Map of URLs to their downloaded data
 - Returns: LanguageModelV3Message
 - Throws: InvalidMessageRoleError for unsupported roles, or errors during conversion
 */
public func convertToLanguageModelMessage(
    message: ModelMessage,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV3Message {
    switch message {
    case .system(let systemMessage):
        return .system(
            content: systemMessage.content,
            providerOptions: systemMessage.providerOptions
        )

    case .user(let userMessage):
        let content: [LanguageModelV3UserMessagePart]

        switch userMessage.content {
        case .text(let text):
            content = [.text(LanguageModelV3TextPart(text: text))]

        case .parts(let parts):
            content = try parts
                .map { part in
                    try convertUserPartToLanguageModelPart(part: part, downloadedAssets: downloadedAssets)
                }
                // Remove empty text parts
                .filter { part in
                    if case .text(let textPart) = part {
                        return !textPart.text.isEmpty
                    }
                    return true
                }
        }

        return .user(content: content, providerOptions: userMessage.providerOptions)

    case .assistant(let assistantMessage):
        let content: [LanguageModelV3MessagePart]

        switch assistantMessage.content {
        case .text(let text):
            content = [.text(LanguageModelV3TextPart(text: text))]

        case .parts(let parts):
            content = try parts
                // Remove empty text parts (no text, and no provider options)
                .filter { part in
                    if case .text(let textPart) = part {
                        return !textPart.text.isEmpty || textPart.providerOptions != nil
                    }
                    return true
                }
                // Remove tool-approval-request (not supported in V3)
                .compactMap { part -> AssistantContentPart? in
                    if case .toolApprovalRequest = part {
                        return nil
                    }
                    return part
                }
                .map { part in
                    try convertAssistantPartToLanguageModelPart(part: part)
                }
        }

        return .assistant(content: content, providerOptions: assistantMessage.providerOptions)

    case .tool(let toolMessage):
        let content: [LanguageModelV3ToolResultPart] = toolMessage.content
            // Remove tool-approval-response (not supported in V3)
            .compactMap { part -> ToolResultPart? in
                if case .toolResult(let result) = part {
                    return result
                }
                return nil
            }
            .map { part in
                LanguageModelV3ToolResultPart(
                    toolCallId: part.toolCallId,
                    toolName: part.toolName,
                    output: part.output,
                    providerOptions: part.providerOptions
                )
            }

        return .tool(content: content, providerOptions: toolMessage.providerOptions)
    }
}

// MARK: - Helper Functions

/**
 Convert user content part to LanguageModelV3UserMessagePart.
 */
private func convertUserPartToLanguageModelPart(
    part: UserContentPart,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV3UserMessagePart {
    switch part {
    case .text(let textPart):
        return .text(LanguageModelV3TextPart(
            text: textPart.text,
            providerOptions: textPart.providerOptions
        ))

    case .image(let imagePart):
        let filePart = try convertMediaPartToLanguageModelFilePart(
            data: imagePart.image,
            mediaType: imagePart.mediaType,
            filename: nil,
            providerOptions: imagePart.providerOptions,
            isImage: true,
            downloadedAssets: downloadedAssets
        )
        return .file(filePart)

    case .file(let filePart):
        let convertedFilePart = try convertMediaPartToLanguageModelFilePart(
            data: filePart.data,
            mediaType: filePart.mediaType,
            filename: filePart.filename,
            providerOptions: filePart.providerOptions,
            isImage: false,
            downloadedAssets: downloadedAssets
        )
        return .file(convertedFilePart)
    }
}

/**
 Convert assistant content part to LanguageModelV3MessagePart.
 */
private func convertAssistantPartToLanguageModelPart(
    part: AssistantContentPart
) throws -> LanguageModelV3MessagePart {
    switch part {
    case .text(let textPart):
        return .text(LanguageModelV3TextPart(
            text: textPart.text,
            providerOptions: textPart.providerOptions
        ))

    case .file(let filePart):
        let (data, mediaType) = try convertToLanguageModelV3DataContent(filePart.data)
        return .file(LanguageModelV3FilePart(
            data: data,
            mediaType: mediaType ?? filePart.mediaType,
            filename: filePart.filename,
            providerOptions: filePart.providerOptions
        ))

    case .reasoning(let reasoningPart):
        return .reasoning(LanguageModelV3ReasoningPart(
            text: reasoningPart.text,
            providerOptions: reasoningPart.providerOptions
        ))

    case .toolCall(let toolCallPart):
        return .toolCall(LanguageModelV3ToolCallPart(
            toolCallId: toolCallPart.toolCallId,
            toolName: toolCallPart.toolName,
            input: toolCallPart.input,
            providerExecuted: toolCallPart.providerExecuted,
            providerOptions: toolCallPart.providerOptions
        ))

    case .toolResult(let toolResultPart):
        return .toolResult(LanguageModelV3ToolResultPart(
            toolCallId: toolResultPart.toolCallId,
            toolName: toolResultPart.toolName,
            output: toolResultPart.output,
            providerOptions: toolResultPart.providerOptions
        ))

    case .toolApprovalRequest:
        // Should be filtered out before this point
        throw InvalidMessageRoleError(
            role: "tool-approval-request",
            message: "Tool approval requests are not supported in LanguageModelV3"
        )
    }
}

/**
 Convert image or file part to LanguageModelV3FilePart.
 */
private func convertMediaPartToLanguageModelFilePart(
    data: DataContentOrURL,
    mediaType: String?,
    filename: String?,
    providerOptions: ProviderOptions?,
    isImage: Bool,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV3FilePart {
    // Convert to LanguageModelV3DataContent
    let (convertedData, convertedMediaType) = try convertToLanguageModelV3DataContent(data)

    var finalMediaType = convertedMediaType ?? mediaType
    var finalData = convertedData

    // If the content is a URL, check if it was downloaded
    if case .url(let url) = finalData {
        let downloadedFile = downloadedAssets[url.absoluteString]
        if let downloadedFile = downloadedFile {
            if downloadedFile.data.isEmpty {
                // Failed download marker - convert URL to string
                finalData = .base64(url.absoluteString)
            } else {
                // Successfully downloaded
                finalData = .data(downloadedFile.data)
                finalMediaType = finalMediaType ?? downloadedFile.mediaType
            }
        }
        // else: URL not in downloadedAssets -> model supports it, keep as URL
    }

    // For images, try to detect media type automatically
    if isImage {
        switch finalData {
        case .data(let bytes):
            finalMediaType = detectMediaType(data: bytes, signatures: imageMediaTypeSignatures) ?? finalMediaType
        case .base64(let base64String):
            if let bytes = Data(base64Encoded: base64String) {
                finalMediaType = detectMediaType(data: bytes, signatures: imageMediaTypeSignatures) ?? finalMediaType
            }
        case .url:
            break
        }
    }

    // For files, mediaType is required
    if !isImage && finalMediaType == nil {
        throw InvalidDataContentError(
            content: "file",
            message: "Media type is missing for file part"
        )
    }

    return LanguageModelV3FilePart(
        data: finalData,
        mediaType: finalMediaType ?? "image/*",  // Default for images
        filename: filename,
        providerOptions: providerOptions
    )
}

/**
 Downloads images and files from URLs in the messages.

 - Parameter messages: Array of ModelMessage to scan for URLs
 - Parameter download: Download function to use
 - Parameter supportedUrls: Map of media types to supported URL patterns
 - Returns: Map of URL strings to downloaded assets
 - Throws: Errors during download operations
 */
private func downloadAssets(
    messages: [ModelMessage],
    download: DownloadFunction,
    supportedUrls: [String: [NSRegularExpression]]
) async throws -> [String: DownloadedAsset] {
    // Extract all user messages with content parts
    let plannedDownloads: [DownloadRequest] = messages
        .compactMap { message -> UserModelMessage? in
            if case .user(let userMessage) = message {
                return userMessage
            }
            return nil
        }
        .compactMap { userMessage -> [UserContentPart]? in
            if case .parts(let parts) = userMessage.content {
                return parts
            }
            return nil
        }
        .flatMap { $0 }
        // Filter only image and file parts
        .compactMap { part -> (mediaType: String?, data: DataContentOrURL)? in
            switch part {
            case .image(let imagePart):
                let mediaType = imagePart.mediaType ?? "image/*"
                return (mediaType: mediaType, data: imagePart.image)

            case .file(let filePart):
                return (mediaType: filePart.mediaType, data: filePart.data)

            case .text:
                return nil
            }
        }
        // Extract URLs
        .compactMap { item -> (mediaType: String?, url: URL)? in
            switch item.data {
            case .url(let url):
                return (mediaType: item.mediaType, url: url)
            case .string(let str):
                // Try to create URL, but only accept if it has a valid http/https scheme
                if let url = URL(string: str),
                   let scheme = url.scheme,
                   (scheme == "http" || scheme == "https") {
                    return (mediaType: item.mediaType, url: url)
                }
                return nil
            case .data:
                return nil
            }
        }
        // Check if URL is supported by model
        .map { item in
            DownloadRequest(
                url: item.url,
                isUrlSupportedByModel: item.mediaType != nil && isUrlSupported(
                    mediaType: item.mediaType!,
                    url: item.url.absoluteString,
                    supportedUrls: supportedUrls
                )
            )
        }

    // Download in parallel
    let downloadedFiles = try await download(plannedDownloads)

    // Build result dictionary
    var result: [String: DownloadedAsset] = [:]
    for (index, file) in downloadedFiles.enumerated() {
        let request = plannedDownloads[index]
        let urlString = request.url.absoluteString

        if let file = file {
            // Successfully downloaded
            result[urlString] = (data: file.data, mediaType: file.mediaType)
        } else if !request.isUrlSupportedByModel {
            // Failed to download, but was supposed to be downloaded
            // Use empty Data as marker (will be converted to string later)
            result[urlString] = (data: Data(), mediaType: nil)
        }
        // If isUrlSupportedByModel == true and file == nil, don't add to result
        // (URL should remain as URL object)
    }

    return result
}

// MARK: - Supporting Types

/// Represents a downloaded asset (data + optional media type)
public typealias DownloadedAsset = (data: Data, mediaType: String?)
