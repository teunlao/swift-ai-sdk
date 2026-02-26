import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/convert-to-alibaba-chat-messages.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

private func formatImageUrl(data: LanguageModelV3DataContent, mediaType: String) -> String {
    switch data {
    case .url(let url):
        return url.absoluteString
    case .base64(let base64):
        return "data:\(mediaType);base64,\(convertToBase64(.string(base64)))"
    case .data(let bytes):
        return "data:\(mediaType);base64,\(convertToBase64(.data(bytes)))"
    }
}

func convertToAlibabaChatMessages(
    prompt: LanguageModelV3Prompt,
    cacheControlValidator: CacheControlValidator? = nil
) throws -> [JSONValue] {
    var messages: [JSONValue] = []
    messages.reserveCapacity(prompt.count)

    for message in prompt {
        switch message {
        case .system(let content, let providerOptions):
            let messageCacheControl = cacheControlValidator?.getCacheControl(providerOptions)
            if let messageCacheControl {
                messages.append(.object([
                    "role": .string("system"),
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(content),
                            "cache_control": messageCacheControl,
                        ])
                    ])
                ]))
            } else {
                messages.append(.object([
                    "role": .string("system"),
                    "content": .string(content),
                ]))
            }

        case .user(let parts, let providerOptions):
            let messageCacheControl = cacheControlValidator?.getCacheControl(providerOptions)
            let isSinglePart = parts.count == 1

            if isSinglePart,
               case .text(let textPart) = parts[0],
               messageCacheControl == nil {
                messages.append(.object([
                    "role": .string("user"),
                    "content": .string(textPart.text),
                ]))
                continue
            }

            var contentParts: [JSONValue] = []
            contentParts.reserveCapacity(parts.count)

            for part in parts {
                let partCacheControl: JSONValue? = {
                    if isSinglePart {
                        return messageCacheControl
                    }
                    switch part {
                    case .text(let textPart):
                        return cacheControlValidator?.getCacheControl(textPart.providerOptions)
                    case .file(let filePart):
                        return cacheControlValidator?.getCacheControl(filePart.providerOptions)
                    }
                }()

                switch part {
                case .text(let textPart):
                    var payload: [String: JSONValue] = [
                        "type": .string("text"),
                        "text": .string(textPart.text),
                    ]
                    if let partCacheControl {
                        payload["cache_control"] = partCacheControl
                    }
                    contentParts.append(.object(payload))

                case .file(let filePart):
                    guard filePart.mediaType.hasPrefix("image/") else {
                        throw UnsupportedFunctionalityError(functionality: "Only image file parts are supported")
                    }

                    let mediaType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType
                    let url = formatImageUrl(data: filePart.data, mediaType: mediaType)

                    var payload: [String: JSONValue] = [
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string(url),
                        ]),
                    ]
                    if let partCacheControl {
                        payload["cache_control"] = partCacheControl
                    }
                    contentParts.append(.object(payload))
                }
            }

            messages.append(.object([
                "role": .string("user"),
                "content": .array(contentParts),
            ]))

        case .assistant(let parts, let providerOptions):
            let messageCacheControl = cacheControlValidator?.getCacheControl(providerOptions)

            var text = ""
            var toolCalls: [JSONValue] = []

            for part in parts {
                switch part {
                case .text(let textPart):
                    text.append(contentsOf: textPart.text)

                case .toolCall(let toolCallPart):
                    toolCalls.append(.object([
                        "id": .string(toolCallPart.toolCallId),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(toolCallPart.toolName),
                            "arguments": .string(jsonStringify(toolCallPart.input) ?? "{}"),
                        ]),
                    ]))

                case .reasoning(let reasoningPart):
                    // Reasoning content can appear in assistant messages during multi-turn conversations.
                    text.append(contentsOf: reasoningPart.text)

                case .file, .toolResult:
                    // Mirror upstream behavior: silently ignore unsupported part types for this prompt conversion.
                    break
                }
            }

            var payload: [String: JSONValue] = [
                "role": .string("assistant"),
            ]

            if let messageCacheControl {
                payload["content"] = .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(text),
                        "cache_control": messageCacheControl,
                    ])
                ])
            } else {
                payload["content"] = text.isEmpty ? .null : .string(text)
            }

            if !toolCalls.isEmpty {
                payload["tool_calls"] = .array(toolCalls)
            }

            messages.append(.object(payload))

        case .tool(let parts, let providerOptions):
            let messageCacheControl = cacheControlValidator?.getCacheControl(providerOptions)

            let toolResponses: [LanguageModelV3ToolResultPart] = parts.compactMap { part in
                switch part {
                case .toolResult(let result):
                    return result
                case .toolApprovalResponse:
                    return nil
                }
            }

            let isSinglePart = toolResponses.count == 1

            for toolResponse in toolResponses {
                let partCacheControl: JSONValue? = {
                    if isSinglePart {
                        return messageCacheControl
                    }
                    return cacheControlValidator?.getCacheControl(toolResponse.providerOptions)
                }()

                let contentValue: String
                switch toolResponse.output {
                case .text(let value, _), .errorText(let value, _):
                    contentValue = value
                case .executionDenied(let reason, _):
                    contentValue = reason ?? "Tool execution denied."
                case .json(let value, _), .errorJson(let value, _):
                    contentValue = jsonStringify(value) ?? "{}"
                case .content(let value, _):
                    contentValue = jsonStringify(value) ?? "[]"
                }

                let content: JSONValue
                if let partCacheControl {
                    content = .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(contentValue),
                            "cache_control": partCacheControl,
                        ])
                    ])
                } else {
                    content = .string(contentValue)
                }

                messages.append(.object([
                    "role": .string("tool"),
                    "tool_call_id": .string(toolResponse.toolCallId),
                    "content": content,
                ]))
            }
        }
    }

    return messages
}

private func jsonStringify<T: Encodable>(_ value: T) -> String? {
    do {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}
