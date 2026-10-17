import Foundation
import AISDKProvider
import AISDKProviderUtils

public func convertToLanguageModelPrompt(
    prompt: StandardizedPrompt,
    supportedUrls: [String: [NSRegularExpression]],
    download: DownloadFunction? = nil
) async throws -> LanguageModelV4Prompt {
    let downloadedAssets = try await downloadAssets(messages: prompt.messages,
        download: download ?? createDefaultDownloadFunction(), supportedUrls: supportedUrls)
    var messages: [LanguageModelV4Message] = []
    switch prompt.instructions {
    case .text(let text): messages.append(.system(content: text, providerOptions: nil))
    case .messages(let systemMessages):
        messages.append(contentsOf: systemMessages.map { .system(content: $0.content, providerOptions: $0.providerOptions) })
    case nil: break
    }
    messages.append(contentsOf: try prompt.messages.map {
        try convertToLanguageModelMessage(message: $0, downloadedAssets: downloadedAssets)
    })
    var combinedMessages: [LanguageModelV4Message] = []
    for message in messages {
        guard case .tool(let content, let providerOptions) = message,
              case .tool(var lastContent, let lastProviderOptions) = combinedMessages.last else {
            combinedMessages.append(message)
            continue
        }
        combinedMessages.removeLast()
        let hadContent = !lastContent.isEmpty
        if hadContent, let lastProviderOptions {
            lastContent[lastContent.count - 1] = lastContent[lastContent.count - 1]
                .withProviderOptions(mergeProviderOptions(lastProviderOptions, lastContent[lastContent.count - 1].providerOptions))
        }
        lastContent.append(contentsOf: content)
        combinedMessages.append(.tool(content: lastContent,
            providerOptions: hadContent ? providerOptions : mergeProviderOptions(lastProviderOptions, providerOptions)))
    }
    var pendingToolCallIds: [String] = []
    for message in combinedMessages {
        switch message {
        case .assistant(let content, _):
            for part in content {
                if case .toolCall(let call) = part, call.providerExecuted != true,
                   !pendingToolCallIds.contains(call.toolCallId) { pendingToolCallIds.append(call.toolCallId) }
            }
        case .tool(let content, _):
            for part in content {
                if case .toolResult(let result) = part { pendingToolCallIds.removeAll { $0 == result.toolCallId } }
            }
        case .user, .system:
            if !pendingToolCallIds.isEmpty { throw MissingToolResultsError(toolCallIds: pendingToolCallIds) }
        }
    }
    if !pendingToolCallIds.isEmpty { throw MissingToolResultsError(toolCallIds: pendingToolCallIds) }
    return combinedMessages.filter {
        if case .tool(let content, _) = $0 { return !content.isEmpty }
        return true
    }
}

private extension LanguageModelV4ToolMessagePart {
    var providerOptions: SharedV4ProviderOptions? {
        switch self {
        case .toolResult(let part): return part.providerOptions
        case .toolApprovalResponse(let part): return part.providerOptions
        }
    }

    func withProviderOptions(_ providerOptions: SharedV4ProviderOptions?) -> LanguageModelV4ToolMessagePart {
        switch self {
        case .toolResult(let part):
            return .toolResult(.init(toolCallId: part.toolCallId, toolName: part.toolName,
                output: part.output, providerOptions: providerOptions))
        case .toolApprovalResponse(let part):
            return .toolApprovalResponse(.init(approvalId: part.approvalId, approved: part.approved,
                reason: part.reason, providerOptions: providerOptions))
        }
    }
}

public func convertToLanguageModelMessage(
    message: ModelMessage,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV4Message {
    switch message {
    case .system(let message):
        return .system(content: message.content, providerOptions: message.providerOptions)
    case .user(let message):
        let content: [LanguageModelV4UserMessagePart]
        switch message.content {
        case .text(let text): content = [.text(.init(text: text))]
        case .parts(let parts):
            content = try parts.map { try convertUserPartToLanguageModelV4Part(part: $0, downloadedAssets: downloadedAssets) }
                .filter {
                    if case .text(let part) = $0 { return !part.text.isEmpty }
                    return true
                }
        }
        return .user(content: content, providerOptions: message.providerOptions)
    case .assistant(let message):
        let content: [LanguageModelV4MessagePart]
        switch message.content {
        case .text(let text): content = [.text(.init(text: text))]
        case .parts(let parts):
            content = try parts.filter {
                if case .text(let part) = $0 { return !part.text.isEmpty || part.providerOptions != nil }
                return true
            }.compactMap { part -> AssistantContentPart? in
                if case .toolApprovalRequest = part { return nil }
                return part
            }.map { try convertAssistantPartToLanguageModelV4Part(part: $0) }
        }
        return .assistant(content: content, providerOptions: message.providerOptions)
    case .tool(let message):
        let content: [LanguageModelV4ToolMessagePart] = message.content.compactMap {
            switch $0 {
            case .toolResult(let result):
                return .toolResult(.init(toolCallId: result.toolCallId, toolName: result.toolName,
                    output: result.output, providerOptions: result.providerOptions))
            case .toolApprovalResponse(let response):
                guard response.providerExecuted == true else { return nil }
                return .toolApprovalResponse(.init(approvalId: response.approvalId, approved: response.approved,
                    reason: response.reason, providerOptions: nil))
            }
        }
        return .tool(content: content, providerOptions: message.providerOptions)
    }
}

private func convertUserPartToLanguageModelV4Part(
    part: UserContentPart,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV4UserMessagePart {
    switch part {
    case .text(let part): return .text(.init(text: part.text, providerOptions: part.providerOptions))
    case .image(let part):
        return .file(try convertMediaPartToLanguageModelV4FilePart(data: part.image, mediaType: part.mediaType,
            filename: nil, providerOptions: part.providerOptions, isImage: true, downloadedAssets: downloadedAssets))
    case .file(let part):
        return .file(try convertMediaPartToLanguageModelV4FilePart(data: part.data, mediaType: part.mediaType,
            filename: part.filename, providerOptions: part.providerOptions, isImage: false, downloadedAssets: downloadedAssets))
    }
}

private func convertAssistantPartToLanguageModelV4Part(part: AssistantContentPart) throws -> LanguageModelV4MessagePart {
    switch part {
    case .text(let part): return .text(.init(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        let (data, mediaType) = try convertToFileData(part.data)
        return .file(.init(data: data, mediaType: mediaType ?? part.mediaType,
            filename: part.filename, providerOptions: part.providerOptions))
    case .custom(let part): return .custom(.init(kind: part.kind, providerOptions: part.providerOptions))
    case .reasoning(let part): return .reasoning(.init(text: part.text, providerOptions: part.providerOptions))
    case .reasoningFile(let part):
        let (data, mediaType) = try convertToLanguageModelV4FileData(part.data)
        return .reasoningFile(.init(data: data, mediaType: mediaType ?? part.mediaType, providerOptions: part.providerOptions))
    case .toolCall(let part):
        return .toolCall(.init(toolCallId: part.toolCallId, toolName: part.toolName, input: part.input,
            providerExecuted: part.providerExecuted, providerOptions: part.providerOptions))
    case .toolResult(let part):
        return .toolResult(.init(toolCallId: part.toolCallId, toolName: part.toolName,
            output: part.output, providerOptions: part.providerOptions))
    case .toolApprovalRequest:
        throw InvalidMessageRoleError(role: "tool-approval-request", message: "Tool approval requests are not supported in LanguageModelV4 prompts")
    }
}

private func convertToLanguageModelV4FileData(_ content: DataContentOrURL) throws -> (data: LanguageModelV4FileData, mediaType: String?) {
    let converted = try convertToFileData(content)
    switch converted.data {
    case .data(let data): return (.data(data), converted.mediaType)
    case .base64(let data): return (.base64(data), converted.mediaType)
    case let .url(url, originalUrl): return (.url(url, originalUrl: originalUrl), converted.mediaType)
    case .text(let text): return (.data(Data(text.utf8)), converted.mediaType)
    case .reference: throw UnsupportedFunctionalityError(functionality: "provider reference file data in reasoning-file prompt part")
    }
}

private func convertMediaPartToLanguageModelV4FilePart(
    data: DataContentOrURL, mediaType: String?, filename: String?, providerOptions: ProviderOptions?, isImage: Bool,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV4FilePart {
    let converted = try convertToFileData(data)
    var mediaType = converted.mediaType ?? mediaType
    var data = converted.data
    if case .url(let url, _) = data, let downloaded = downloadedAssets[url.absoluteString] {
        if downloaded.data.isEmpty { data = .base64(url.absoluteString) }
        else { data = .data(downloaded.data); mediaType = mediaType ?? downloaded.mediaType }
    }
    if isImage {
        switch data {
        case .data(let bytes): mediaType = detectMediaType(data: bytes, signatures: imageMediaTypeSignatures) ?? mediaType
        case .base64(let base64):
            if let bytes = Data(base64Encoded: base64) { mediaType = detectMediaType(data: bytes, signatures: imageMediaTypeSignatures) ?? mediaType }
        case .text(let text): mediaType = detectMediaType(data: Data(text.utf8), signatures: imageMediaTypeSignatures) ?? mediaType
        case .url, .reference: break
        }
    }
    if !isImage && mediaType == nil { throw InvalidDataContentError(content: "file", message: "Media type is missing for file part") }
    return .init(data: data, mediaType: mediaType ?? "image/*", filename: filename, providerOptions: providerOptions)
}

private func downloadAssets(
    messages: [ModelMessage], download: DownloadFunction, supportedUrls: [String: [NSRegularExpression]]
) async throws -> [String: DownloadedAsset] {
    let plannedDownloads: [DownloadRequest] = messages.compactMap { message -> UserModelMessage? in
        if case .user(let message) = message { return message }
        return nil
    }.compactMap { message -> [UserContentPart]? in
        if case .parts(let parts) = message.content { return parts }
        return nil
    }.flatMap { $0 }.compactMap { part -> (mediaType: String?, data: DataContentOrURL)? in
        switch part {
        case .image(let part): return (part.mediaType ?? "image/*", part.image)
        case .file(let part): return (part.mediaType, part.data)
        case .text: return nil
        }
    }.compactMap { item -> (mediaType: String?, url: URL)? in
        switch item.data {
        case .url(let url): return (item.mediaType, url)
        case .string(let value):
            if let url = URL(string: value), let scheme = url.scheme, scheme == "http" || scheme == "https" { return (item.mediaType, url) }
            return nil
        case .data, .reference, .text: return nil
        }
    }.map { item in
        DownloadRequest(url: item.url, isUrlSupportedByModel: item.mediaType != nil && isUrlSupported(
            mediaType: item.mediaType!, url: item.url.absoluteString, supportedUrls: supportedUrls))
    }
    let files = try await download(plannedDownloads)
    var result: [String: DownloadedAsset] = [:]
    for (index, file) in files.enumerated() {
        let request = plannedDownloads[index]
        if let file { result[request.url.absoluteString] = (file.data, file.mediaType) }
        else if !request.isUrlSupportedByModel {
            // Empty data marks an unsuccessful requested download.
            result[request.url.absoluteString] = (Data(), nil)
        }
    }
    return result
}

public typealias DownloadedAsset = (data: Data, mediaType: String?)
