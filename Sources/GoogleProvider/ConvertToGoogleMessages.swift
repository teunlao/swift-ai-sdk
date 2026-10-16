import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleMessagesOptions: Sendable, Equatable {
    public var isGemmaModel: Bool
    public var providerOptionsName: String
    public var supportsFunctionResponseParts: Bool
    public var includeFunctionCallIds: Bool
    public var isGemini3Model: Bool
    public var supportsGoogleCloudStorageUrls: Bool

    public init(
        isGemmaModel: Bool = false,
        providerOptionsName: String = "google",
        supportsFunctionResponseParts: Bool = true,
        includeFunctionCallIds: Bool = true,
        isGemini3Model: Bool = false,
        supportsGoogleCloudStorageUrls: Bool = false
    ) {
        self.isGemmaModel = isGemmaModel
        self.providerOptionsName = providerOptionsName
        self.supportsFunctionResponseParts = supportsFunctionResponseParts
        self.includeFunctionCallIds = includeFunctionCallIds
        self.isGemini3Model = isGemini3Model
        self.supportsGoogleCloudStorageUrls = supportsGoogleCloudStorageUrls
    }
}

func convertToGoogleMessages(
    _ prompt: LanguageModelV4Prompt,
    options: GoogleMessagesOptions = .init(),
    onWarning: ((SharedV4Warning) -> Void)? = nil
) throws -> GooglePrompt {
    var system: [GoogleSystemInstructionPart] = []
    var contents: [GoogleContent] = []
    var systemAllowed = true
    var missingSignatures: [String] = []
    let vertex = options.providerOptionsName != "google"
    func readOptions(_ values: SharedV4ProviderOptions?) -> [String: JSONValue] {
        let names = vertex ? ["googleVertex", "vertex", "google"] : ["google", "googleVertex", "vertex"]
        return names.compactMap { values?[$0] }.first ?? [:]
    }
    func signature(_ values: [String: JSONValue]) throws -> String? {
        guard let value = values["thoughtSignature"], value != .null else { return nil }
        if case .string(let string) = value { return string }
        return try googleJSONString(value)
    }
    func serverPart(_ key: String, metadata: [String: JSONValue], value: JSONValue, signature: String?) -> GoogleContentPart? {
        guard let id = metadata["serverToolCallId"], id != .null,
              let type = metadata["serverToolType"], type != .null else { return nil }
        var result: [String: JSONValue] = [key: .object([
            "id": id, "toolType": type, key == "toolCall" ? "args" : "response": value
        ])]
        if let signature { result["thoughtSignature"] = .string(signature) }
        return .raw(.object(result))
    }
    func filePart(_ file: LanguageModelV4FilePart, thought: Bool? = nil, signature: String? = nil, assistant: Bool = false) throws -> GoogleContentPart {
        switch file.data {
        case .url(let url, let original):
            if assistant { throw UnsupportedFunctionalityError(functionality: "File data URLs in assistant messages are not supported") }
            return .fileData(.init(mimeType: try resolveFullMediaType(part: file), fileURI: url.scheme == "gs" ? original ?? url.absoluteString : url.absoluteString))
        case .reference(let reference):
            if vertex { throw UnsupportedFunctionalityError(functionality: "file parts with provider references") }
            var result: [String: JSONValue] = ["fileData": .object([
                "mimeType": .string(try resolveFullMediaType(part: file)),
                "fileUri": .string(try resolveProviderReference(reference: reference, provider: "google"))
            ])]
            if let thought { result["thought"] = .bool(thought) }
            if let signature { result["thoughtSignature"] = .string(signature) }
            return .raw(.object(result))
        case .text(let text):
            return .inlineData(.init(mimeType: isFullMediaType(file.mediaType) ? file.mediaType : "text/plain", data: Data(text.utf8).base64EncodedString(), thoughtSignature: signature, thought: thought))
        case .data(let data):
            return .inlineData(.init(mimeType: assistant ? file.mediaType : try resolveFullMediaType(part: file), data: data.base64EncodedString(), thoughtSignature: signature, thought: thought))
        case .base64(let data):
            return .inlineData(.init(mimeType: assistant ? file.mediaType : try resolveFullMediaType(part: file), data: data, thoughtSignature: signature, thought: thought))
        }
    }
    for message in prompt {
        switch message {
        case .system(let text, _):
            guard systemAllowed else { throw UnsupportedFunctionalityError(functionality: "system messages are only supported at the beginning of the conversation") }
            system.append(.init(text: text))
        case .user(let parts, _):
            systemAllowed = false
            contents.append(.init(role: .user, parts: try parts.map { part in
                switch part {
                case .text(let text): return .text(.init(text: text.text))
                case .file(let file): return try filePart(file)
                }
            }))
        case .assistant(let parts, _):
            systemAllowed = false
            var signedCall = false
            var converted: [GoogleContentPart] = []
            for part in parts {
                switch part {
                case .text(let text):
                    if !text.text.isEmpty { converted.append(.text(.init(text: text.text, thoughtSignature: try signature(readOptions(text.providerOptions))))) }
                case .reasoning(let text):
                    if !text.text.isEmpty { converted.append(.text(.init(text: text.text, thought: true, thoughtSignature: try signature(readOptions(text.providerOptions))))) }
                case .reasoningFile(let file):
                    let sig = try signature(readOptions(file.providerOptions))
                    switch file.data {
                    case .url: throw UnsupportedFunctionalityError(functionality: "File data URLs in assistant messages are not supported")
                    case .data(let data): converted.append(.inlineData(.init(mimeType: file.mediaType, data: data.base64EncodedString(), thoughtSignature: sig, thought: true)))
                    case .base64(let data): converted.append(.inlineData(.init(mimeType: file.mediaType, data: data, thoughtSignature: sig, thought: true)))
                    }
                case .file(let file):
                    let metadata = readOptions(file.providerOptions)
                    converted.append(try filePart(file, thought: metadata["thought"] == .bool(true) ? true : nil, signature: try signature(metadata), assistant: true))
                case .toolCall(let call):
                    let metadata = readOptions(call.providerOptions)
                    if call.providerExecuted == true && call.toolName == "code_execution" {
                        let input = try googleParsedJSON(call.input)
                        guard case .object(let object) = input, case .string = object["code"], case .string = object["language"] else {
                            throw TypeValidationError(value: input, cause: SchemaValidationIssuesError(vendor: "google", issues: "invalid code execution input"))
                        }
                        converted.append(.raw(.object(["executableCode": input])))
                        continue
                    }
                    let originalSignature = try signature(metadata)
                    let server = metadata["serverToolCallId"] != nil && metadata["serverToolType"] != nil
                    var sig = originalSignature
                    if sig == nil && options.isGemini3Model && (server || !signedCall) {
                        sig = "skip_thought_signature_validator"
                        missingSignatures.append(call.toolName)
                    }
                    if !server && originalSignature != nil { signedCall = true }
                    if let part = serverPart("toolCall", metadata: metadata, value: try googleParsedJSON(call.input), signature: sig) {
                        converted.append(part)
                    } else {
                        converted.append(.functionCall(.init(id: options.includeFunctionCallIds ? call.toolCallId : nil, name: call.toolName, arguments: call.input, thoughtSignature: sig)))
                    }
                case .toolResult(let result):
                    let metadata = readOptions(result.providerOptions)
                    let value: JSONValue
                    if case .json(let json, _) = result.output { value = json } else { value = .object([:]) }
                    if result.toolName == "code_execution", case .json = result.output {
                        guard case .object(let object) = value, case .string = object["outcome"], case .string = object["output"] else {
                            throw TypeValidationError(value: value, cause: SchemaValidationIssuesError(vendor: "google", issues: "invalid code execution output"))
                        }
                        converted.append(.raw(.object(["codeExecutionResult": value])))
                    } else if let part = serverPart("toolResponse", metadata: metadata, value: value, signature: try signature(metadata)) {
                        converted.append(part)
                    }
                case .custom: break
                }
            }
            contents.append(.init(role: .model, parts: converted))
        case .tool(let parts, _):
            systemAllowed = false
            var converted: [GoogleContentPart] = []
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let metadata = readOptions(result.providerOptions)
                let output = result.output
                if let last = contents.indices.last, contents[last].role == .model,
                   let server = serverPart("toolResponse", metadata: metadata, value: {
                       if case .json(let value, _) = output { return value }
                       return .object([:])
                   }(), signature: try signature(metadata)) {
                    contents[last].parts.append(server)
                    continue
                }
                if case .content(let values) = output {
                    try appendGoogleToolResult(&converted, result: result, values: values, options: options)
                } else {
                    let value: JSONValue
                    let error: Bool
                    switch output {
                    case .text(let text, _): value = .string(text); error = false
                    case .json(let json, _): value = try googleFunctionResponseValue(json); error = false
                    case .errorText(let text, _): value = .string(text); error = true
                    case .errorJson(let json, _): value = try googleFunctionResponseValue(json); error = true
                    case .executionDenied(let reason, _): value = .string(reason ?? "Tool call execution denied."); error = true
                    case .content: continue
                    }
                    converted.append(.functionResponse(.init(
                        id: options.includeFunctionCallIds ? result.toolCallId : nil,
                        name: result.toolName,
                        response: .object(["name": .string(result.toolName), error ? "error" : "content": value])
                    )))
                }
            }
            contents.append(.init(role: .user, parts: converted))
        }
    }
    if options.isGemmaModel, !system.isEmpty, contents.first?.role == .user {
        contents[0].parts.insert(.text(.init(text: system.map(\.text).joined(separator: "\n\n") + "\n\n")), at: 0)
    }
    if !missingSignatures.isEmpty {
        var unique: [String] = []
        for name in missingSignatures where !unique.contains(name) { unique.append(name) }
        onWarning?(.other(message: "Replayed \(missingSignatures.count) `functionCall` part(s) for a Gemini 3 model without a `thoughtSignature` (tools: \(unique.map { "`\($0)`" }.joined(separator: ", "))). Injected the documented `skip_thought_signature_validator` sentinel to keep the request from failing with HTTP 400. The likely cause is application code that drops `providerOptions.google.thoughtSignature` when persisting or serializing assistant tool-call messages. See https://ai.google.dev/gemini-api/docs/thought-signatures."))
    }
    return .init(systemInstruction: system.isEmpty || options.isGemmaModel ? nil : .init(parts: system), contents: contents)
}

func googleJSONString(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return String(decoding: try encoder.encode(GoogleJSONText(value: value)), as: UTF8.self)
}

// JSON.stringify encodes non-finite numbers as null.
private struct GoogleJSONText: Encodable {
    let value: JSONValue
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .string(let string): try container.encode(string)
        case .number(let number):
            if number.isFinite { try container.encode(number == 0 ? 0 : number) }
            else { try container.encodeNil() }
        case .array(let array): try container.encode(array.map { GoogleJSONText(value: $0) })
        case .object(let object): try container.encode(object.mapValues { GoogleJSONText(value: $0) })
        }
    }
}

private func googleParsedJSON(_ value: JSONValue) throws -> JSONValue {
    if case .string(let text) = value { return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    return value
}

private func googleFunctionResponseValue(_ value: JSONValue) throws -> JSONValue {
    func hasReference(_ value: JSONValue) -> Bool {
        switch value {
        case .object(let object): return object["$ref"] != nil || object.values.contains(where: hasReference)
        case .array(let values): return values.contains(where: hasReference)
        default: return false
        }
    }
    return hasReference(value) ? .string(try googleJSONString(value)) : value
}

private func appendGoogleToolResult(
    _ parts: inout [GoogleContentPart],
    result: LanguageModelV4ToolResultPart,
    values: [LanguageModelV4ToolResultContentPart],
    options: GoogleMessagesOptions
) throws {
    var text: [String] = []
    var media: [JSONValue] = []
    for value in values {
        switch value {
        case .text(let string, _):
            if options.supportsFunctionResponseParts { text.append(string) }
            else { parts.append(.functionResponse(.init(id: options.includeFunctionCallIds ? result.toolCallId : nil, name: result.toolName, response: .object(["name": .string(result.toolName), "content": .string(string)])))) }
        case .file(let data, let mediaType, _, _):
            let file = LanguageModelV4FilePart(data: data, mediaType: mediaType)
            var inline: (String, String)?
            var uri: String?
            switch data {
            case .data(let bytes): inline = (try resolveFullMediaType(part: file), bytes.base64EncodedString())
            case .base64(let bytes): inline = (try resolveFullMediaType(part: file), bytes)
            case .url(let url, let original):
                if options.supportsFunctionResponseParts {
                    if url.scheme == "data", let comma = url.absoluteString.firstIndex(of: ","), url.absoluteString[..<comma].hasSuffix(";base64") {
                        inline = (String(url.absoluteString.dropFirst(5).prefix(while: { $0 != ";" })), String(url.absoluteString[url.absoluteString.index(after: comma)...]))
                    } else if options.supportsGoogleCloudStorageUrls && url.scheme == "gs" && ["image/png", "image/jpeg", "image/webp", "application/pdf", "text/plain"].contains(mediaType) {
                        uri = original ?? url.absoluteString
                    }
                }
            default: break
            }
            if let inline {
                if options.supportsFunctionResponseParts {
                    media.append(.object(["inlineData": .object(["mimeType": .string(inline.0), "data": .string(inline.1)])]))
                } else {
                    parts.append(.inlineData(.init(mimeType: inline.0, data: inline.1)))
                    parts.append(.text(.init(text: "Tool executed successfully and returned this \(getTopLevelMediaType(mediaType) == "image" ? "image" : "file") as a response")))
                }
            } else if let uri {
                media.append(.object(["fileData": .object(["mimeType": .string(mediaType), "fileUri": .string(uri)])]))
            } else if let encoded = try? JSONEncoder().encode(value), let serialized = String(data: encoded, encoding: .utf8) {
                if options.supportsFunctionResponseParts { text.append(serialized) } else { parts.append(.text(.init(text: serialized))) }
            }
        case .custom:
            let encoded = try JSONEncoder().encode(value)
            let serialized = String(decoding: encoded, as: UTF8.self)
            if options.supportsFunctionResponseParts { text.append(serialized) } else { parts.append(.text(.init(text: serialized))) }
        }
    }
    if options.supportsFunctionResponseParts {
        var response: [String: JSONValue] = ["name": .string(result.toolName), "response": .object([
            "name": .string(result.toolName), "content": .string(text.isEmpty ? "Tool executed successfully." : text.joined(separator: "\n"))
        ])]
        if options.includeFunctionCallIds { response["id"] = .string(result.toolCallId) }
        if !media.isEmpty { response["parts"] = .array(media) }
        parts.append(.raw(.object(["functionResponse": .object(response)])))
    }
}
