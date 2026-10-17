import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class HuggingFaceResponsesLanguageModel: LanguageModelV4 {
    private let modelIdentifier: HuggingFaceResponsesModelId
    private let config: HuggingFaceConfig

    init(modelId: HuggingFaceResponsesModelId, config: HuggingFaceConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { ["image/*": [try NSRegularExpression(pattern: "^https?://.*$")]] }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareArguments(options: options)
        var body = prepared.body
        body["stream"] = .bool(false)
        let url = config.url(.init(modelId: modelId, path: "/responses"))
        let response = try await postJsonToAPI(
            url: url,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: huggingfaceFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: responsesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        let value = response.value
        if let error = value.error, error.isTruthy {
            let responseBody = try response.rawValue.map { raw in
                if let text = raw as? String { return text }
                return String(decoding: try JSONEncoder().encode(jsonValue(from: raw)), as: UTF8.self)
            }
            throw APICallError(
                message: error.objectValue?["message"]?.stringValue ?? String(describing: error),
                url: url,
                requestBodyValues: body,
                statusCode: 400,
                responseHeaders: response.responseHeaders,
                responseBody: responseBody,
                isRetryable: false
            )
        }

        var content: [LanguageModelV4Content] = []
        for item in value.output {
            switch item {
            case .message(let message):
                for part in message.content {
                    content.append(.text(.init(text: part.text, providerMetadata: itemMetadata(message.id))))
                    for annotation in part.annotations ?? [] {
                        guard let url = annotation.objectValue?["url"]?.stringValue else { continue }
                        content.append(.source(.url(
                            id: config.generateId?() ?? generateID(),
                            url: url,
                            title: annotation.objectValue?["title"]?.stringValue,
                            providerMetadata: nil
                        )))
                    }
                }
            case .reasoning(let reasoning):
                for part in reasoning.content {
                    content.append(.reasoning(.init(text: part.text, providerMetadata: itemMetadata(reasoning.id))))
                }
            case .mcpCall(let call):
                content.append(.toolCall(.init(
                    toolCallId: call.id, toolName: call.name, input: call.arguments, providerExecuted: true
                )))
                if let output = call.output, !output.isEmpty {
                    content.append(.toolResult(.init(toolCallId: call.id, toolName: call.name, result: .string(output))))
                }
            case .functionCall(let call):
                content.append(.toolCall(.init(toolCallId: call.callId, toolName: call.name, input: call.arguments)))
                if let output = call.output, !output.isEmpty {
                    content.append(.toolResult(.init(toolCallId: call.callId, toolName: call.name, result: .string(output))))
                }
            case .mcpListTools(let list):
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let input = String(decoding: try encoder.encode(["server_label": list.serverLabel]), as: UTF8.self)
                content.append(.toolCall(.init(toolCallId: list.id, toolName: "list_tools", input: input, providerExecuted: true)))
                if let tools = list.tools {
                    content.append(.toolResult(.init(toolCallId: list.id, toolName: "list_tools", result: .object(["tools": .array(tools)]))))
                }
            }
        }

        return LanguageModelV4GenerateResult(
            content: content,
            finishReason: finishReason(value.incompleteDetails?.reason),
            usage: convertResponsesUsage(value.usage?.raw),
            providerMetadata: responseMetadata(.string(value.id)),
            request: .init(body: body),
            response: .init(
                id: value.id,
                timestamp: Date(timeIntervalSince1970: value.createdAt),
                modelId: value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareArguments(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelId, path: "/responses")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: huggingfaceFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: responsesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))
            let task = Task {
                var finish = LanguageModelV4FinishReason(unified: .other, raw: nil)
                var usage: JSONValue?
                var responseId: JSONValue? = .null
                do {
                    for try await result in response.value {
                        switch result {
                        case .failure(let error, _):
                            finish = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .error(error)))
                        case .success(let chunk, _):
                            switch chunk {
                            case .providerError(let error):
                                let raw: String?
                                switch error.code {
                                case .string(let code): raw = code
                                case .number(let code): raw = try streamErrorCodeString(code)
                                case nil: raw = error.type
                                }
                                finish = .init(unified: .error, raw: raw)
                                continuation.yield(.error(error: .providerStreamError(error)))
                            case .created(let metadata):
                                responseId = .string(metadata.id)
                                continuation.yield(.responseMetadata(
                                    id: metadata.id, modelId: metadata.model,
                                    timestamp: Date(timeIntervalSince1970: metadata.createdAt)
                                ))
                            case .itemAdded(let item):
                                switch item {
                                case .message(let id, let role) where role == "assistant":
                                    continuation.yield(.textStart(id: id, providerMetadata: itemMetadata(id)))
                                case .functionStart(let call):
                                    continuation.yield(.toolInputStart(
                                        id: call.callId, toolName: call.name, providerMetadata: nil,
                                        providerExecuted: nil, dynamic: nil, title: nil
                                    ))
                                case .reasoning(let id):
                                    continuation.yield(.reasoningStart(id: id, providerMetadata: itemMetadata(id)))
                                default: break
                                }
                            case .itemDone(let item):
                                switch item {
                                case .message(let id, let role) where role == "assistant":
                                    continuation.yield(.textEnd(id: id, providerMetadata: nil))
                                case .functionCall(let call):
                                    continuation.yield(.toolInputEnd(id: call.callId, providerMetadata: nil))
                                    continuation.yield(.toolCall(.init(toolCallId: call.callId, toolName: call.name, input: call.arguments)))
                                    if let output = call.output, output.isTruthy {
                                        continuation.yield(.toolResult(.init(toolCallId: call.callId, toolName: call.name, result: output)))
                                    }
                                default: break
                                }
                            case .completed(let completed):
                                responseId = completed.id
                                finish = finishReason(completed.reason)
                                if let completedUsage = completed.usage, completedUsage.isTruthy { usage = completedUsage }
                            case .textDelta(let id, let delta):
                                continuation.yield(.textDelta(id: id, delta: delta, providerMetadata: nil))
                            case .reasoningDelta(let id, let delta):
                                continuation.yield(.reasoningDelta(id: id, delta: delta, providerMetadata: nil))
                            case .reasoningEnd(let id):
                                continuation.yield(.reasoningEnd(id: id, providerMetadata: nil))
                            case .other: break
                            }
                        }
                    }
                    continuation.yield(.finish(finishReason: finish, usage: convertResponsesUsage(usage), providerMetadata: responseMetadata(responseId)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return LanguageModelV4StreamResult(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }

    private func prepareArguments(options: LanguageModelV4CallOptions) async throws -> (body: [String: JSONValue], warnings: [SharedV4Warning]) {
        var warnings: [SharedV4Warning] = []
        if options.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
        if options.presencePenalty != nil { warnings.append(.unsupported(feature: "presencePenalty", details: nil)) }
        if options.frequencyPenalty != nil { warnings.append(.unsupported(feature: "frequencyPenalty", details: nil)) }
        if options.stopSequences != nil { warnings.append(.unsupported(feature: "stopSequences", details: nil)) }
        let converted = try convertToHuggingFaceResponsesMessages(prompt: options.prompt)
        warnings.append(contentsOf: converted.warnings)
        let providerOptions = try await parseProviderOptions(
            provider: "huggingface", providerOptions: options.providerOptions, schema: huggingfaceLanguageModelResponsesOptions
        )
        let tools = prepareHuggingFaceResponsesTools(tools: options.tools, toolChoice: options.toolChoice)
        warnings.append(contentsOf: tools.warnings)
        var body: [String: JSONValue] = ["model": .string(modelId), "input": converted.input]
        if let temperature = options.temperature { body["temperature"] = .number(temperature) }
        if let topP = options.topP { body["top_p"] = .number(topP) }
        if let maxOutputTokens = options.maxOutputTokens { body["max_output_tokens"] = .number(Double(maxOutputTokens)) }
        if let metadata = providerOptions?.metadata { body["metadata"] = .object(metadata.mapValues(JSONValue.string)) }
        if let instructions = providerOptions?.instructions { body["instructions"] = .string(instructions) }
        if let effort = providerOptions?.reasoningEffort { body["reasoning"] = .object(["effort": .string(effort)]) }
        if case let .json(schema?, name, description) = options.responseFormat {
            var format: [String: JSONValue] = [
                "type": .string("json_schema"), "strict": .bool(providerOptions?.strictJsonSchema ?? false),
                "name": .string(name ?? "response"), "schema": schema
            ]
            if let description { format["description"] = .string(description) }
            body["text"] = .object(["format": .object(format)])
        }
        if let preparedTools = tools.tools { body["tools"] = preparedTools }
        if let choice = tools.toolChoice { body["tool_choice"] = choice }
        return (body, warnings)
    }
}

private func itemMetadata(_ id: String) -> SharedV4ProviderMetadata {
    ["huggingface": ["itemId": .string(id)]]
}

private func responseMetadata(_ id: JSONValue?) -> SharedV4ProviderMetadata {
    var metadata: [String: JSONValue] = [:]
    metadata["responseId"] = id
    return ["huggingface": metadata]
}

private func finishReason(_ raw: String?) -> LanguageModelV4FinishReason {
    .init(unified: mapHuggingFaceResponsesFinishReason(raw ?? "stop"), raw: raw)
}

private func streamErrorCodeString(_ value: Double) throws -> String {
    if value == 0 { return "0" }
    let encoded = String(value).lowercased()
    let sign = encoded.hasPrefix("-") ? "-" : ""
    let magnitude = sign.isEmpty ? encoded[...] : encoded.dropFirst()
    let parts = magnitude.split(separator: "e", maxSplits: 1)
    let exponent: Int
    if parts.count == 2 {
        guard let parsed = Int(parts[1]) else {
            throw InvalidResponseDataError(data: encoded, message: "Invalid numeric stream error code")
        }
        exponent = parsed
    } else { exponent = 0 }
    let integerDigits = parts[0].prefix { $0 != "." }.count
    let rawDigits = parts[0].filter { $0 != "." }
    let zeros = rawDigits.prefix { $0 == "0" }.count
    var digits = rawDigits.dropFirst(zeros)
    while digits.last == "0" { digits = digits.dropLast() }
    let position = integerDigits + exponent - zeros
    let power = position - 1
    // Provider error codes use ECMAScript's decimal/exponent thresholds.
    if power >= -6 && power < 21 {
        if position <= 0 { return sign + "0." + String(repeating: "0", count: -position) + digits }
        if position >= digits.count { return sign + digits + String(repeating: "0", count: position - digits.count) }
        let point = digits.index(digits.startIndex, offsetBy: position)
        return sign + digits[..<point] + "." + digits[point...]
    }
    let tail = digits.dropFirst()
    let coefficient = String(digits.prefix(1)) + (tail.isEmpty ? "" : "." + tail)
    return sign + coefficient + "e" + (power >= 0 ? "+" : "") + String(power)
}

private func convertResponsesUsage(_ value: JSONValue?) -> LanguageModelV4Usage {
    guard let raw = value, raw != .null else { return .init() }
    let usage = raw.objectValue ?? [:]
    func defaultedCount(_ value: JSONValue?) -> Double? {
        switch value {
        case .none, .some(.null): 0
        case .some(.number(let value)): value
        default: nil
        }
    }
    func project(_ value: Double?) -> Int? { value.flatMap { Int(exactly: $0) } }
    func subtract(_ lhs: Double?, _ rhs: Double?) -> Int? {
        guard let lhs, let rhs else { return nil }
        if let left = Int(exactly: lhs), let right = Int(exactly: rhs) {
            let difference = left.subtractingReportingOverflow(right)
            return difference.overflow ? nil : difference.partialValue
        }
        return Int(exactly: lhs - rhs)
    }
    let input = usage["input_tokens"]?.numberValue
    let output = usage["output_tokens"]?.numberValue
    let cached = defaultedCount(usage["input_tokens_details"]?.objectValue?["cached_tokens"])
    let reasoning = defaultedCount(usage["output_tokens_details"]?.objectValue?["reasoning_tokens"])
    return .init(
        inputTokens: .init(total: project(input), noCache: subtract(input, cached), cacheRead: project(cached)),
        outputTokens: .init(total: project(output), text: subtract(output, reasoning), reasoning: project(reasoning)),
        raw: raw
    )
}

private let responsesResponseSchema = FlexibleSchema(
    Schema<ResponsesResponse>.codable(ResponsesResponse.self, jsonSchema: .object(["type": .string("object")]))
)
private let responsesChunkSchema = FlexibleSchema(
    Schema<ResponsesChunk>.codable(ResponsesChunk.self, jsonSchema: .object(["type": .string("object")]))
)

private struct ResponsesResponse: Decodable {
    struct IncompleteDetails: Decodable { let reason: String }
    let id: String
    let model: String
    let createdAt: Double
    let error: JSONValue?
    let incompleteDetails: IncompleteDetails?
    let usage: ResponsesUsage?
    let output: [ResponsesOutput]

    private enum CodingKeys: String, CodingKey {
        case id, model, object, status, error, tools, temperature, output, usage
        case createdAt = "created_at", incompleteDetails = "incomplete_details", topP = "top_p", outputText = "output_text"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        model = try container.decode(String.self, forKey: .model)
        createdAt = try container.decode(Double.self, forKey: .createdAt)
        _ = try container.decode(String.self, forKey: .object)
        _ = try container.decode(String.self, forKey: .status)
        _ = try container.decode([JSONValue].self, forKey: .tools)
        _ = try container.decode(Double.self, forKey: .temperature)
        _ = try container.decode(Double.self, forKey: .topP)
        _ = try container.decodeIfPresent(String.self, forKey: .outputText)
        error = try container.decodeIfPresent(JSONValue.self, forKey: .error)
        incompleteDetails = try container.decodeIfPresent(IncompleteDetails.self, forKey: .incompleteDetails)
        usage = try container.decodeIfPresent(ResponsesUsage.self, forKey: .usage)
        output = try container.decode([ResponsesOutput].self, forKey: .output)
    }
}

private struct ResponsesUsage: Decodable {
    let raw: JSONValue

    private struct InputDetails: Decodable { let cached_tokens: Double }
    private struct OutputDetails: Decodable { let reasoning_tokens: Double }
    private enum CodingKeys: String, CodingKey {
        case input_tokens, output_tokens, total_tokens, input_tokens_details, output_tokens_details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var value: [String: JSONValue] = [
            "input_tokens": .number(try container.decode(Double.self, forKey: .input_tokens)),
            "output_tokens": .number(try container.decode(Double.self, forKey: .output_tokens)),
            "total_tokens": .number(try container.decode(Double.self, forKey: .total_tokens))
        ]
        if let details = try container.decodeOptional(InputDetails.self, forKey: .input_tokens_details) {
            value["input_tokens_details"] = .object(["cached_tokens": .number(details.cached_tokens)])
        }
        if let details = try container.decodeOptional(OutputDetails.self, forKey: .output_tokens_details) {
            value["output_tokens_details"] = .object(["reasoning_tokens": .number(details.reasoning_tokens)])
        }
        raw = .object(value)
    }
}

private enum ResponsesOutput: Decodable {
    struct Text: Decodable {
        let text: String
        let annotations: [JSONValue]?
        private enum CodingKeys: String, CodingKey { case type, text, annotations }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(String.self, forKey: .type) == "output_text" else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected output_text")
            }
            text = try container.decode(String.self, forKey: .text)
            annotations = try container.decodeOptional([JSONValue].self, forKey: .annotations)
        }
    }
    struct ReasoningText: Decodable {
        let text: String
        private enum CodingKeys: String, CodingKey { case type, text }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(String.self, forKey: .type) == "reasoning_text" else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected reasoning_text")
            }
            text = try container.decode(String.self, forKey: .text)
        }
    }
    struct Message: Decodable {
        let id: String
        let content: [Text]
        private enum CodingKeys: String, CodingKey { case id, role, content }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            _ = try container.decodeOptional(String.self, forKey: .role)
            content = try container.decode([Text].self, forKey: .content)
        }
    }
    struct Reasoning: Decodable {
        struct Summary: Decodable {
            let text: String
            private enum CodingKeys: String, CodingKey { case type, text }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                guard try container.decode(String.self, forKey: .type) == "reasoning_summary" else {
                    throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected reasoning_summary")
                }
                text = try container.decode(String.self, forKey: .text)
            }
        }
        let id: String
        let content: [ReasoningText]
        private enum CodingKeys: String, CodingKey { case id, content, summary }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            content = try container.decode([ReasoningText].self, forKey: .content)
            _ = try container.decodeOptional([Summary].self, forKey: .summary)
        }
    }
    struct MCPCall: Decodable {
        let id: String
        let name: String
        let arguments: String
        let output: String?
        private enum CodingKeys: String, CodingKey { case id, name, arguments, output }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            arguments = try container.decode(String.self, forKey: .arguments)
            output = try container.decodeOptional(String.self, forKey: .output)
        }
    }
    struct MCPListTools: Decodable {
        let id: String
        let serverLabel: String
        let tools: [JSONValue]?
        private enum CodingKeys: String, CodingKey { case id, tools, serverLabel = "server_label" }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            serverLabel = try container.decode(String.self, forKey: .serverLabel)
            tools = try container.decodeOptional([JSONValue].self, forKey: .tools)
        }
    }
    case message(Message)
    case reasoning(Reasoning)
    case mcpCall(MCPCall)
    case functionCall(ResponsesFunctionCall)
    case mcpListTools(MCPListTools)

    private enum CodingKeys: String, CodingKey { case type, id, status }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(String.self, forKey: .id)
        _ = try container.decodeOptional(String.self, forKey: .status)
        switch try container.decode(String.self, forKey: .type) {
        case "message": self = .message(try Message(from: decoder))
        case "reasoning": self = .reasoning(try Reasoning(from: decoder))
        case "mcp_call": self = .mcpCall(try MCPCall(from: decoder))
        case "function_call": self = .functionCall(try ResponsesFunctionCall(from: decoder))
        case "mcp_list_tools": self = .mcpListTools(try MCPListTools(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown Responses output type")
        }
    }
}

private struct ResponsesFunctionCall: Decodable {
    let callId: String
    let name: String
    let arguments: String
    let output: String?
    private enum CodingKeys: String, CodingKey { case id, name, arguments, output, callId = "call_id" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        name = try container.decode(String.self, forKey: .name)
        arguments = try container.decode(String.self, forKey: .arguments)
        output = try container.decodeOptional(String.self, forKey: .output)
    }
}

private enum ResponsesChunk: Decodable {
    struct Metadata: Decodable {
        let id: String
        let model: String
        let createdAt: Double
        private enum CodingKeys: String, CodingKey { case id, model, createdAt = "created_at" }
    }
    struct Completion {
        let id: JSONValue?
        let reason: String?
        let usage: JSONValue?
    }
    struct FunctionStart: Decodable {
        let callId: String
        let name: String
        private enum CodingKeys: String, CodingKey { case callId = "call_id", name }
    }
    struct FunctionCall: Decodable {
        let callId: String
        let name: String
        let arguments: String
        let output: JSONValue?
        private enum CodingKeys: String, CodingKey { case callId = "call_id", name, arguments, output }
    }
    enum Item {
        case message(id: String, role: String?)
        case reasoning(id: String)
        case functionStart(FunctionStart)
        case functionCall(FunctionCall)
        case other
    }
    case providerError(ProviderStreamError)
    case created(Metadata)
    case itemAdded(Item)
    case itemDone(Item)
    case textDelta(id: String, delta: String)
    case reasoningDelta(id: String, delta: String)
    case reasoningEnd(id: String)
    case completed(Completion)
    case other

    private enum CodingKeys: String, CodingKey { case type, response, item }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let raw = try JSONValue(from: decoder)
        let object = raw.objectValue ?? [:]
        if type == "error" || type == "response.failed" {
            let details = type == "response.failed"
                ? object["response"]?.objectValue?["error"]?.objectValue
                : object["error"]?.recordValue ?? object
            if let details, let message = details["message"]?.stringValue {
                let code: ProviderStreamError.Code?
                switch details["code"] {
                case .string(let value): code = .string(value)
                case .number(let value): code = .number(value)
                default: code = nil
                }
                self = .providerError(createProviderStreamError(message: message, type: type, code: code, data: raw))
                return
            }
        }
        // Upstream's loose fallback dispatches known events even when unused fields are missing.
        switch type {
        case "response.created":
            self = .created(try container.decode(Metadata.self, forKey: .response))
        case "response.completed":
            if let response = try? container.decode(ResponsesResponse.self, forKey: .response) {
                self = .completed(.init(id: .string(response.id), reason: response.incompleteDetails?.reason, usage: response.usage?.raw))
            } else if let response = object["response"]?.objectValue {
                let usage = response["usage"] == .null ? Optional<JSONValue>.none : response["usage"]
                self = .completed(.init(id: response["id"], reason: response["incomplete_details"]?.objectValue?["reason"]?.stringValue, usage: usage))
            } else {
                self = .other
            }
        case "response.output_item.added", "response.output_item.done":
            let item: Item
            if let value = object["item"]?.objectValue {
                switch value["type"]?.stringValue {
                case "message":
                    guard let id = value["id"]?.stringValue else { self = .other; return }
                    item = .message(id: id, role: value["role"]?.stringValue)
                case "reasoning":
                    guard let id = value["id"]?.stringValue else { self = .other; return }
                    item = .reasoning(id: id)
                case "function_call":
                    item = type == "response.output_item.added"
                        ? .functionStart(try container.decode(FunctionStart.self, forKey: .item))
                        : .functionCall(try container.decode(FunctionCall.self, forKey: .item))
                default: item = .other
                }
            } else { item = .other }
            self = type == "response.output_item.added" ? .itemAdded(item) : .itemDone(item)
        case "response.output_text.delta", "response.reasoning_text.delta":
            guard let id = object["item_id"]?.stringValue, let delta = object["delta"]?.stringValue else { self = .other; return }
            self = type == "response.output_text.delta" ? .textDelta(id: id, delta: delta) : .reasoningDelta(id: id, delta: delta)
        case "response.reasoning_text.done":
            guard let id = object["item_id"]?.stringValue else { self = .other; return }
            self = .reasoningEnd(id: id)
        default: self = .other
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeOptional<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        contains(key) ? try decode(type, forKey: key) : nil
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
    var recordValue: [String: JSONValue]? {
        switch self {
        case .object(let value): value
        case .array: [:]
        default: nil
        }
    }
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    var isTruthy: Bool {
        switch self {
        case .null: false
        case .bool(let value): value
        case .string(let value): !value.isEmpty
        case .number(let value): value != 0
        case .array, .object: true
        }
    }
}
