import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertToXAIResponsesInput(
    prompt: LanguageModelV4Prompt,
    store: Bool? = nil
) async throws -> (input: XAIResponsesInput, warnings: [SharedV4Warning]) {
    var input: XAIResponsesInput = []
    var warnings: [SharedV4Warning] = []

    for message in prompt {
        switch message {
        case .system(let content, _):
            input.append(.object(["role": .string("system"), "content": .string(content)]))
        case .user(let parts, _):
            var content: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let text):
                    content.append(.object(["type": .string("input_text"), "text": .string(text.text)]))
                case .file(let file):
                    switch file.data {
                    case .reference(let reference):
                        content.append(.object([
                            "type": .string("input_file"),
                            "file_id": .string(try resolveProviderReference(reference: reference, provider: "xai"))
                        ]))
                    case .text:
                        throw UnsupportedFunctionalityError(functionality: "text file parts")
                    case .url(let url, let original):
                        if getTopLevelMediaType(file.mediaType) == "image" {
                            content.append(try await imageInput(url: original ?? url.absoluteString, providerOptions: file.providerOptions))
                        } else {
                            content.append(.object(["type": .string("input_file"), "file_url": .string(original ?? url.absoluteString)]))
                        }
                    case .data, .base64:
                        guard getTopLevelMediaType(file.mediaType) == "image" else {
                            throw UnsupportedFunctionalityError(functionality: "file part media type \(file.mediaType) as inline data (xAI Responses requires a URL or a Files API reference for non-image files)")
                        }
                        content.append(try await imageInput(url: try imageDataURL(file.data, mediaType: file.mediaType)!, providerOptions: file.providerOptions))
                    }
                }
            }
            input.append(.object(["role": .string("user"), "content": .array(content)]))
        case .assistant(let parts, _):
            for part in parts {
                switch part {
                case .text(let text):
                    var payload: [String: JSONValue] = ["role": .string("assistant"), "content": .string(text.text)]
                    if case .string(let id) = text.providerOptions?["xai"]?["itemId"] { payload["id"] = .string(id) }
                    input.append(.object(payload))
                case .toolCall(let call):
                    if call.providerExecuted == true { continue }
                    let id: String
                    if case .string(let value) = call.providerOptions?["xai"]?["itemId"] { id = value } else { id = call.toolCallId }
                    input.append(.object([
                        "type": .string("function_call"), "id": .string(id), "call_id": .string(call.toolCallId),
                        "name": .string(call.toolName), "arguments": .string(try stringifyJSONValue(call.input)), "status": .string("completed")
                    ]))
                case .toolResult:
                    break
                case .reasoning(let reasoning):
                    let metadata = reasoning.providerOptions?["xai"] ?? [:]
                    let id = metadata["itemId"].flatMap { if case .string(let value) = $0 { value } else { nil } }
                    let encrypted = metadata["reasoningEncryptedContent"].flatMap { if case .string(let value) = $0 { value } else { nil } }
                    if id != nil || encrypted != nil {
                        var payload: [String: JSONValue] = [
                            "type": .string("reasoning"), "id": .string(id ?? ""), "status": .string("completed"),
                            "summary": .array(reasoning.text.isEmpty ? [] : [.object(["type": .string("summary_text"), "text": .string(reasoning.text)])])
                        ]
                        if let encrypted { payload["encrypted_content"] = .string(encrypted) }
                        input.append(.object(payload))
                    } else {
                        warnings.append(.other(message: "Reasoning parts without itemId or encrypted content cannot be sent back to xAI. Skipping."))
                    }
                case .file:
                    warnings.append(.other(message: "xAI Responses API does not support file in assistant messages"))
                case .reasoningFile:
                    warnings.append(.other(message: "xAI Responses API does not support reasoning-file in assistant messages"))
                case .custom:
                    warnings.append(.other(message: "xAI Responses API does not support custom in assistant messages"))
                }
            }
        case .tool(let parts, _):
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let output: JSONValue
                switch result.output {
                case .text(let value, _), .errorText(let value, _): output = .string(value)
                case .executionDenied(let reason, _): output = .string(reason ?? "tool execution denied")
                case .json(let value, _), .errorJson(let value, _): output = .string(try stringifyJSONValue(value))
                case .content(let parts):
                    output = .array(try parts.compactMap { item in
                        switch item {
                        case .text(let text, _): return .object(["type": .string("input_text"), "text": .string(text)])
                        case .file(let data, let mediaType, _, _):
                            guard getTopLevelMediaType(mediaType) == "image", let url = try imageDataURL(data, mediaType: mediaType) else { return nil }
                            return .object(["type": .string("input_image"), "image_url": .string(url)])
                        case .custom: return nil
                        }
                    })
                }
                input.append(.object(["type": .string("function_call_output"), "call_id": .string(result.toolCallId), "output": output]))
            }
        }
    }
    return (input, warnings)
}

private func imageInput(url: String, providerOptions: SharedV4ProviderOptions?) async throws -> JSONValue {
    var payload: [String: JSONValue] = ["type": .string("input_image"), "image_url": .string(url)]
    let options = try await parseProviderOptions(provider: "xai", providerOptions: providerOptions, schema: xaiFilePartOptionsSchema)
    if let detail = options?.imageDetail { payload["detail"] = .string(detail.rawValue) }
    return .object(payload)
}

private func imageDataURL(_ data: SharedV4FileData, mediaType: String) throws -> String? {
    switch data {
    case .url(let url, let original): return original ?? url.absoluteString
    case .data(let bytes):
        let type = try resolveFullMediaType(part: .init(data: data, mediaType: mediaType))
        return "data:\(type);base64,\(bytes.base64EncodedString())"
    case .base64(let bytes):
        let type = try resolveFullMediaType(part: .init(data: data, mediaType: mediaType))
        return "data:\(type);base64,\(bytes)"
    case .reference, .text: return nil
    }
}

private func stringifyJSONValue(_ value: JSONValue) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

public struct XAIFilePartProviderOptions: Codable, Sendable, Equatable {
    public enum ImageDetail: String, Codable, Sendable { case low, high, auto }
    public var imageDetail: ImageDetail?
    public init(imageDetail: ImageDetail? = nil) { self.imageDetail = imageDetail }
}

private let xaiFilePartOptionsSchema = FlexibleSchema(Schema<XAIFilePartProviderOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        guard case .object(let object) = json, object["imageDetail"] != .null else { throw InvalidArgumentError(argument: "imageDetail", message: "Expected low, high, or auto") }
        return .success(value: try JSONDecoder().decode(XAIFilePartProviderOptions.self, from: JSONEncoder().encode(json)))
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))
