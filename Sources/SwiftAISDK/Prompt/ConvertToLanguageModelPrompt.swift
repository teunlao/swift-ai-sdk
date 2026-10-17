import Foundation
import AISDKProvider
import AISDKProviderUtils

public func convertToLanguageModelPrompt(
    prompt: StandardizedPrompt,
    supportedUrls: [String: [NSRegularExpression]],
    download: DownloadFunction? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil
) async throws -> LanguageModelV4Prompt {
    let downloadedAssets = try await downloadAssets(messages: prompt.messages,
        download: download ?? createDefaultDownloadFunction(abortSignal: abortSignal), supportedUrls: supportedUrls)
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
            }.map { try convertAssistantPartToLanguageModelV4Part(part: $0, downloadedAssets: downloadedAssets) }
        }
        return .assistant(content: content, providerOptions: message.providerOptions)
    case .tool(let message):
        let content: [LanguageModelV4ToolMessagePart] = try message.content.compactMap {
            switch $0 {
            case .toolResult(let result):
                return .toolResult(.init(toolCallId: result.toolCallId, toolName: result.toolName,
                    output: try convertToolResultOutput(result.output, downloadedAssets: downloadedAssets),
                    providerOptions: result.providerOptions))
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
        let converted = try convertToFileData(part.image)
        let file = try convertFileToLanguageModelV4File(data: converted.data,
            mediaType: converted.mediaType ?? part.mediaType ?? "image/*", downloadedAssets: downloadedAssets)
        return .file(.init(data: file.data, mediaType: file.mediaType, providerOptions: part.providerOptions))
    case .file(let part):
        let converted = try convertToFileData(part.data)
        let file = try convertFileToLanguageModelV4File(data: converted.data,
            mediaType: converted.mediaType ?? part.mediaType, downloadedAssets: downloadedAssets)
        return .file(.init(data: file.data, mediaType: file.mediaType, filename: part.filename,
            providerOptions: part.providerOptions))
    }
}

/// Files in tool results go through the same conversion as user files, so a model that
/// cannot fetch URLs receives the downloaded bytes.
private func convertToolResultOutput(
    _ output: LanguageModelV4ToolResultOutput,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV4ToolResultOutput {
    guard case .content(let parts) = output else { return output }
    return .content(value: try parts.map { part in
        guard case let .file(data, mediaType, filename, providerOptions) = part else { return part }
        let normalized = try normalizeFileData(data)
        let file = try convertFileToLanguageModelV4File(data: normalized.data,
            mediaType: normalized.mediaType ?? mediaType, downloadedAssets: downloadedAssets)
        return .file(data: file.data, mediaType: file.mediaType, filename: filename, providerOptions: providerOptions)
    })
}

/// Extracts the bytes and media type of a data URL; other file data passes unchanged.
private func normalizeFileData(_ data: SharedV4FileData) throws -> (data: SharedV4FileData, mediaType: String?) {
    if case .url(let url, _) = data, url.scheme == "data" {
        return try convertToFileData(.url(url))
    }
    return (data, nil)
}

/// Port of upstream `convertPartToLanguageModelPart`: a downloaded URL becomes its bytes, the
/// download's Content-Type completes a missing or partial media type, and image bytes name
/// their own image type.
private func convertFileToLanguageModelV4File(
    data: SharedV4FileData,
    mediaType: String?,
    downloadedAssets: [String: DownloadedAsset]
) throws -> (data: SharedV4FileData, mediaType: String) {
    var data = data
    var mediaType = mediaType
    if case .url(let url, _) = data, let downloaded = downloadedAssets[url.absoluteString] {
        data = .data(downloaded.data)
        if let downloadedMediaType = downloaded.mediaType, mediaType.map(isFullMediaType) != true {
            mediaType = downloadedMediaType
        }
    }
    let imageMediaType: String?
    switch data {
    case .data(let bytes): imageMediaType = detectMediaType(data: bytes, topLevelType: "image")
    case .base64(let base64): imageMediaType = detectMediaType(data: base64, topLevelType: "image")
    case .url, .text, .reference: imageMediaType = nil
    }
    if let imageMediaType { mediaType = imageMediaType }
    guard let mediaType else {
        throw InvalidDataContentError(content: "file", message: "Media type is missing for file part")
    }
    return (data, mediaType)
}

private func convertAssistantPartToLanguageModelV4Part(
    part: AssistantContentPart,
    downloadedAssets: [String: DownloadedAsset]
) throws -> LanguageModelV4MessagePart {
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
            output: try convertToolResultOutput(part.output, downloadedAssets: downloadedAssets),
            providerOptions: part.providerOptions))
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

/// Downloads the URL files of user messages and of tool results; a nil download result leaves its URL as is.
private func downloadAssets(
    messages: [ModelMessage], download: DownloadFunction, supportedUrls: [String: [NSRegularExpression]]
) async throws -> [String: DownloadedAsset] {
    var files: [(mediaType: String?, data: SharedV4FileData)] = []
    func collect(_ output: LanguageModelV4ToolResultOutput) throws {
        guard case .content(let parts) = output else { return }
        for case let .file(data, mediaType, _, _) in parts {
            files.append((mediaType, try normalizeFileData(data).data))
        }
    }
    for message in messages {
        switch message {
        case .user(let message):
            guard case .parts(let parts) = message.content else { continue }
            for part in parts {
                switch part {
                case .image(let part): files.append((part.mediaType ?? "image/*", try convertToFileData(part.image).data))
                case .file(let part): files.append((part.mediaType, try convertToFileData(part.data).data))
                case .text: break
                }
            }
        case .tool(let message):
            for case .toolResult(let result) in message.content { try collect(result.output) }
        case .assistant(let message):
            guard case .parts(let parts) = message.content else { continue }
            for case .toolResult(let result) in parts { try collect(result.output) }
        case .system:
            break
        }
    }
    let plannedDownloads: [DownloadRequest] = files.compactMap { file in
        guard case .url(let url, _) = file.data else { return nil }
        return DownloadRequest(url: url, isUrlSupportedByModel: file.mediaType.map {
            isUrlSupported(mediaType: $0, url: url.absoluteString, supportedUrls: supportedUrls)
        } ?? false)
    }
    let downloaded = try await download(plannedDownloads)
    var result: [String: DownloadedAsset] = [:]
    for (request, file) in zip(plannedDownloads, downloaded) {
        if let file { result[request.url.absoluteString] = (file.data, file.mediaType) }
    }
    return result
}

public typealias DownloadedAsset = (data: Data, mediaType: String?)
