/**
 Serialize prompt content for OpenTelemetry tracing.

 Port of `@ai-sdk/ai/src/telemetry/stringify-for-telemetry.ts`.

 Helper utility to serialize prompt content for OpenTelemetry tracing.
 It converts Data content in file parts to base64 strings, since JSON
 cannot directly represent binary data.

 This is necessary because normalized LanguageModelV3Prompt carries
 images/files as Data, which needs special handling for JSON serialization.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Stringify prompt for telemetry
///
/// Converts prompt to JSON string, transforming Data content to base64 strings.
///
/// - Parameter prompt: The prompt to stringify
/// - Returns: JSON string representation
public func stringifyForTelemetry(_ prompt: LanguageModelV3Prompt) throws -> String {
    // Transform prompt to ensure Data is converted to base64
    let transformedPrompt = prompt.map { message in
        transformMessage(message)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]  // Sorted keys, no slash escaping
    let data = try encoder.encode(transformedPrompt)

    guard let jsonString = String(data: data, encoding: .utf8) else {
        throw EncodingError.invalidValue(
            prompt,
            EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert encoded data to UTF-8 string"
            )
        )
    }

    return jsonString
}

// MARK: - Private Helpers

/// Transform message to convert Data in file parts to base64
private func transformMessage(_ message: LanguageModelV3Message) -> LanguageModelV3Message {
    switch message {
    case .system:
        // System messages have string content, no transformation needed
        return message

    case .user(let content, let providerOptions):
        let transformedContent = content.map { transformUserMessagePart($0) }
        return .user(content: transformedContent, providerOptions: providerOptions)

    case .assistant(let content, let providerOptions):
        let transformedContent = content.map { transformMessagePart($0) }
        return .assistant(content: transformedContent, providerOptions: providerOptions)

    case .tool(let content, let providerOptions):
        // Tool result parts don't contain Data, no transformation needed
        return .tool(content: content, providerOptions: providerOptions)
    }
}

/// Transform user message part (text or file)
private func transformUserMessagePart(_ part: LanguageModelV3UserMessagePart) -> LanguageModelV3UserMessagePart {
    switch part {
    case .text:
        return part
    case .file(let filePart):
        return .file(transformFilePart(filePart))
    }
}

/// Transform message part (text, file, reasoning, tool-call, tool-result)
private func transformMessagePart(_ part: LanguageModelV3MessagePart) -> LanguageModelV3MessagePart {
    switch part {
    case .text, .reasoning, .toolCall, .toolResult:
        // These don't contain Data, no transformation needed
        return part
    case .file(let filePart):
        return .file(transformFilePart(filePart))
    }
}

/// Transform file part to convert Data to base64
private func transformFilePart(_ part: LanguageModelV3FilePart) -> LanguageModelV3FilePart {
    let transformedData: LanguageModelV3DataContent

    switch part.data {
    case .data(let data):
        // Convert Data to base64 string for JSON serialization
        let base64String = data.base64EncodedString()
        transformedData = .base64(base64String)
    case .base64, .url:
        // Already in serializable format
        transformedData = part.data
    }

    return LanguageModelV3FilePart(
        data: transformedData,
        mediaType: part.mediaType,
        filename: part.filename,
        providerOptions: part.providerOptions
    )
}
