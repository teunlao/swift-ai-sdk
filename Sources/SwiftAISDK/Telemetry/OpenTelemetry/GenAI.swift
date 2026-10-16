import Foundation
import AISDKProvider
import AISDKProviderUtils

// The telemetry boundary projects SDK messages into GenAI semantic conventions.
enum GenAI {
    static func provider(_ provider: String) -> String {
        let lower = provider.lowercased()
        let prefixes = [
            ("google.vertex", "gcp.vertex_ai"), ("google.generative-ai", "gcp.gemini"),
            ("google-vertex", "gcp.vertex_ai"), ("amazon-bedrock", "aws.bedrock"),
            ("azure-openai", "azure.ai.openai"), ("anthropic", "anthropic"),
            ("openai", "openai"), ("azure", "azure.ai.inference"), ("google", "gcp.gemini"),
            ("mistral", "mistral_ai"), ("cohere", "cohere"), ("bedrock", "aws.bedrock"),
            ("groq", "groq"), ("deepseek", "deepseek"), ("perplexity", "perplexity"), ("xai", "x_ai"),
        ]
        for (prefix, mapped) in prefixes where lower == prefix || lower.hasPrefix(prefix + ".") || lower.hasPrefix(prefix + "-") {
            return mapped
        }
        return provider
    }

    static func operation(_ id: String) -> String {
        switch id {
        case "ai.generateText", "ai.streamText", "ai.generateObject", "ai.streamObject": "invoke_agent"
        case "ai.embed", "ai.embedMany": "embeddings"
        case "ai.rerank": "rerank"
        default: id
        }
    }

    static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    static func value<T: Encodable>(_ value: T) -> JSONValue {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value), let result = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return result
    }

    static func text(_ text: String, type: String = "text") -> JSONValue {
        .object(["type": .string(type), "content": .string(text)])
    }

    static func message(_ role: String, _ parts: [JSONValue]) -> JSONValue {
        .object(["role": .string(role), "parts": .array(parts)])
    }

    static func instructions(_ instructions: Instructions) -> [JSONValue] {
        switch instructions {
        case .text(let content): [text(content)]
        case .messages(let messages): messages.map { text($0.content) }
        }
    }

    static func messages(prompt: PromptContent? = nil, messages: [ModelMessage]? = nil) -> [JSONValue] {
        var result: [JSONValue] = []
        switch prompt {
        case .text(let content): result.append(message("user", [text(content)]))
        case .messages(let messages): result += messages.map(modelMessage)
        case nil: break
        }
        result += (messages ?? []).map(modelMessage)
        return result
    }

    private static func modelMessage(_ model: ModelMessage) -> JSONValue {
        switch model {
        case .system(let model): return message("system", [text(model.content)])
        case .user(let model):
            switch model.content {
            case .text(let content): return message("user", [text(content)])
            case .parts(let parts):
                return message("user", parts.map { part in
                    switch part {
                    case .text(let part): text(part.text)
                    case .image(let part): file(part.image, mediaType: part.mediaType, modality: "image")
                    case .file(let part): file(part.data, mediaType: part.mediaType)
                    }
                })
            }
        case .assistant(let model):
            switch model.content {
            case .text(let content): return message("assistant", [text(content)])
            case .parts(let parts):
                return message("assistant", parts.map { part in
                    switch part {
                    case .text(let part): text(part.text)
                    case .reasoning(let part): text(part.text, type: "reasoning")
                    case .toolCall(let part): toolCall(id: part.toolCallId, name: part.toolName, input: part.input)
                    case .toolResult(let part): toolResponse(id: part.toolCallId, output: response(part.output))
                    case .custom: .object(["type": .string("custom")])
                    case .file: .object(["type": .string("file")])
                    case .reasoningFile: .object(["type": .string("reasoning-file")])
                    case .toolApprovalRequest: .object(["type": .string("tool-approval-request")])
                    }
                })
            }
        case .tool(let model):
            return message("tool", model.content.map { part in
                switch part {
                case .toolResult(let part): toolResponse(id: part.toolCallId, output: response(part.output))
                case .toolApprovalResponse: .object(["type": .string("tool-approval-response")])
                }
            })
        }
    }

    static func inputMessages(_ prompt: LanguageModelV4Prompt) -> [JSONValue] {
        prompt.map { model in
            switch model {
            case .system(let content, _): return message("system", [text(content)])
            case .user(let content, _):
                return message("user", content.map { part in
                    switch part {
                    case .text(let part): text(part.text)
                    case .file(let part): file(part.data, mediaType: part.mediaType)
                    }
                })
            case .assistant(let content, _):
                return message("assistant", content.map { part in
                    switch part {
                    case .text(let part): text(part.text)
                    case .reasoning(let part): text(part.text, type: "reasoning")
                    case .file(let part): file(part.data, mediaType: part.mediaType)
                    case .custom(let part): .object(["type": .string("custom"), "kind": .string(part.kind)])
                    case .reasoningFile: .object(["type": .string("reasoning-file")])
                    case .toolCall(let part): toolCall(id: part.toolCallId, name: part.toolName, input: part.input)
                    case .toolResult(let part): toolResponse(id: part.toolCallId, output: response(part.output))
                    }
                })
            case .tool(let content, _):
                return message("tool", content.map { part in
                    switch part {
                    case .toolResult(let part): return toolResponse(id: part.toolCallId, output: response(part.output))
                    case .toolApprovalResponse(let part):
                        var result: JSONObject = ["type": .string("tool_approval_response"), "approval_id": .string(part.approvalId), "approved": .bool(part.approved)]
                        if let reason = part.reason { result["reason"] = .string(reason) }
                        return .object(result)
                    }
                })
            }
        }
    }

    private static func response<T: Encodable>(_ output: T) -> JSONValue {
        let encoded = value(output)
        guard case .object(let object) = encoded else { return encoded }
        switch object["type"] {
        case .string("text"), .string("error-text"), .string("json"), .string("error-json"): return object["value"] ?? .null
        case .string("execution-denied"):
            var result: JSONObject = ["denied": .bool(true)]
            if let reason = object["reason"] { result["reason"] = reason }
            return .object(result)
        default: return encoded
        }
    }

    private static func modality(_ mediaType: String?) -> String {
        if let mediaType {
            for prefix in ["image", "video", "audio"] where mediaType.hasPrefix(prefix + "/") { return prefix }
        }
        return "image"
    }

    private static func blob(_ content: String, mediaType: String?, modality: String? = nil, uri: Bool = false) -> JSONValue {
        .object([
            "type": .string(uri ? "uri" : "blob"), "modality": .string(modality ?? self.modality(mediaType)),
            "mime_type": mediaType.map(JSONValue.string) ?? .null, uri ? "uri" : "content": .string(content),
        ])
    }

    private static func file(_ data: DataContentOrURL, mediaType: String?, modality: String? = nil) -> JSONValue {
        switch data {
        case .data(let data): blob(data.base64EncodedString(), mediaType: mediaType, modality: modality)
        case .string(let text), .text(let text): blob(text, mediaType: mediaType, modality: modality, uri: text.hasPrefix("http://") || text.hasPrefix("https://"))
        case .url(let url): blob(url.absoluteString, mediaType: mediaType, modality: modality, uri: true)
        case .reference: blob("", mediaType: mediaType, modality: modality)
        }
    }

    private static func file(_ data: SharedV4FileData, mediaType: String) -> JSONValue {
        switch data {
        case .data(let data): return blob(data.base64EncodedString(), mediaType: mediaType)
        case .base64(let text): return blob(text, mediaType: mediaType, uri: text.hasPrefix("http://") || text.hasPrefix("https://"))
        case .url(let url, _): return blob(url.absoluteString, mediaType: mediaType, uri: true)
        case .text(let text): return blob(text, mediaType: mediaType, uri: text.hasPrefix("http://") || text.hasPrefix("https://"))
        case .reference: return blob("", mediaType: mediaType)
        }
    }

    static func toolCall(id: String, name: String, input: JSONValue) -> JSONValue {
        .object(["type": .string("tool_call"), "id": .string(id), "name": .string(name), "arguments": input])
    }

    static func toolResponse(id: String, output: JSONValue) -> JSONValue {
        .object(["type": .string("tool_call_response"), "id": .string(id), "response": output])
    }

    static func output(text content: String?, reasoning: [ReasoningOutput] = [], toolCalls: [TypedToolCall] = [], toolResults: [TypedToolResult] = [], files: [GeneratedFile] = [], finishReason: FinishReason) -> [JSONValue] {
        var parts = reasoning.filter { !$0.text.isEmpty }.map { text($0.text, type: "reasoning") }
        if let content, !content.isEmpty { parts.append(text(content)) }
        parts += toolCalls.map { toolCall(id: $0.toolCallId, name: $0.toolName, input: $0.input) }
        parts += toolResults.map { toolResponse(id: $0.toolCallId, output: $0.output) }
        parts += files.map { blob($0.base64, mediaType: $0.mediaType) }
        return output(parts: parts, finishReason: finishReason)
    }

    static func objectOutput(_ content: String, finishReason: FinishReason) -> [JSONValue] {
        output(parts: [text(content)], finishReason: finishReason)
    }

    private static func output(parts: [JSONValue], finishReason: FinishReason) -> [JSONValue] {
        let mapped: String
        switch finishReason.rawValue {
        case "content-filter": mapped = "content_filter"
        case "tool-calls": mapped = "tool_call"
        case "other", "unknown": mapped = "stop"
        default: mapped = finishReason.rawValue
        }
        return [.object(["role": .string("assistant"), "parts": .array(parts), "finish_reason": .string(mapped)])]
    }
}
