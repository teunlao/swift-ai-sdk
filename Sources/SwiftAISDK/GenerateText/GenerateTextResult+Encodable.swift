import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - DefaultGenerateTextResult + Encodable

extension DefaultGenerateTextResult: Encodable where OutputValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        let json = GenerateTextResultJSONEncoder.serialize(result: self)
        try json.encode(to: encoder)
    }
}

public extension DefaultGenerateTextResult where OutputValue: Encodable {
    /// Returns the full generateText result as a JSONValue mirroring the TypeScript object shape.
    func jsonValue() -> JSONValue {
        GenerateTextResultJSONEncoder.serialize(result: self)
    }

    /// Serialises the result to a JSON string, matching `JSON.stringify` behaviour.
    /// - Parameters:
    ///   - prettyPrinted: Adds whitespace/newlines like `JSON.stringify(_, null, 2)`.
    ///   - sortedKeys: Ensures deterministic key ordering for easier diffs.
    func jsonString(prettyPrinted: Bool = true, sortedKeys: Bool = true) throws -> String {
        let json = jsonValue()
        let data = try json.toJSONData(prettyPrinted: prettyPrinted, sortedKeys: sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - JSON Serialization Helpers

private enum GenerateTextResultJSONEncoder {
    static func serialize<OutputValue: Encodable>(result: DefaultGenerateTextResult<OutputValue>) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["text"] = .string(result.text)
        object["content"] = .array(result.content.map(contentPart))
        object["reasoning"] = .array(result.reasoning.map(reasoningOutput))
        object["reasoningText"] = optionalString(result.reasoningText) ?? .null
        object["files"] = .array(result.files.map(generatedFile))
        object["sources"] = .array(result.sources.map(source))
        object["toolCalls"] = .array(result.toolCalls.map(toolCall))
        object["staticToolCalls"] = .array(result.staticToolCalls.map { toolCall(.static($0)) })
        object["dynamicToolCalls"] = .array(result.dynamicToolCalls.map { toolCall(.dynamic($0)) })
        object["toolResults"] = .array(result.toolResults.map(toolResult))
        object["staticToolResults"] = .array(result.staticToolResults.map { toolResult(.static($0)) })
        object["dynamicToolResults"] = .array(result.dynamicToolResults.map { toolResult(.dynamic($0)) })
        object["finishReason"] = .string(result.finishReason.rawValue)
        object["usage"] = usage(result.usage)
        object["totalUsage"] = usage(result.totalUsage)
        object["warnings"] = warnings(result.warnings)
        object["request"] = request(result.request)
        object["response"] = response(result.response)
        object["providerMetadata"] = encodedProviderMetadata(result.providerMetadata) ?? .null
        object["steps"] = .array(result.steps.enumerated().map { index, step in stepJSON(step, index: index + 1) })

        if let experimental = try? result.experimentalOutput,
           let experimentalJSON = jsonValue(from: experimental) {
            object["experimentalOutput"] = experimentalJSON
        } else {
            object["experimentalOutput"] = .null
        }

        return .object(object)
    }

    // MARK: - Steps

    private static func stepJSON(_ step: StepResult, index: Int) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["index"] = .number(Double(index))
        object["content"] = .array(step.content.map(contentPart))
        object["text"] = .string(step.text)
        object["reasoning"] = .array(step.reasoning.map(reasoningOutput))
        object["reasoningText"] = optionalString(step.reasoningText) ?? .null
        object["files"] = .array(step.files.map(generatedFile))
        object["sources"] = .array(step.sources.map(source))
        object["toolCalls"] = .array(step.toolCalls.map(toolCall))
        object["staticToolCalls"] = .array(step.staticToolCalls.map { toolCall(.static($0)) })
        object["dynamicToolCalls"] = .array(step.dynamicToolCalls.map { toolCall(.dynamic($0)) })
        object["toolResults"] = .array(step.toolResults.map(toolResult))
        object["staticToolResults"] = .array(step.staticToolResults.map { toolResult(.static($0)) })
        object["dynamicToolResults"] = .array(step.dynamicToolResults.map { toolResult(.dynamic($0)) })
        object["finishReason"] = .string(step.finishReason.rawValue)
        object["usage"] = usage(step.usage)
        object["warnings"] = warnings(step.warnings)
        object["request"] = request(step.request)
        object["response"] = response(step.response)
        object["providerMetadata"] = encodedProviderMetadata(step.providerMetadata) ?? .null
        return .object(object)
    }

    // MARK: - Content Parts

    private static func contentPart(_ part: ContentPart) -> JSONValue {
        switch part {
        case let .text(text, metadata):
            return object([
                "type": .string("text"),
                "text": .string(text),
                "providerMetadata": encodedProviderMetadata(metadata)
            ])
        case let .reasoning(reasoning):
            return reasoningOutput(reasoning)
        case let .source(_, sourceValue):
            return sourceValueJSON(sourceValue)
        case let .file(file, metadata):
            var map = generatedFileMap(file)
            if let data = encodedProviderMetadata(metadata) {
                map["providerMetadata"] = data
            }
            return .object(map)
        case let .toolCall(call, metadata):
            return merge(toolCall(call), providerMetadata: metadata)
        case let .toolResult(result, metadata):
            return merge(toolResult(result), providerMetadata: metadata)
        case let .toolError(error, metadata):
            return merge(toolError(error), providerMetadata: metadata)
        case let .toolApprovalRequest(request):
            return toolApprovalRequest(request)
        }
    }

    private static func reasoningOutput(_ reasoning: ReasoningOutput) -> JSONValue {
        object([
            "type": .string("reasoning"),
            "text": .string(reasoning.text),
            "providerMetadata": encodedProviderMetadata(reasoning.providerMetadata)
        ])
    }

    private static func generatedFile(_ file: GeneratedFile) -> JSONValue {
        .object(generatedFileMap(file))
    }

    private static func generatedFileMap(_ file: GeneratedFile) -> [String: JSONValue] {
        [
            "type": .string("file"),
            "mediaType": .string(file.mediaType),
            "base64": .string(file.base64)
        ]
    }

    private static func source(_ source: Source) -> JSONValue {
        sourceValueJSON(source)
    }

    private static func sourceValueJSON(_ source: Source) -> JSONValue {
        jsonValue(from: source) ?? .null
    }

    private static func toolCall(_ call: TypedToolCall) -> JSONValue {
        switch call {
        case .static(let staticCall):
            return toolCall(staticCall: staticCall)
        case .dynamic(let dynamicCall):
            return toolCall(dynamicCall: dynamicCall)
        }
    }

    private static func toolCall(staticCall: StaticToolCall) -> JSONValue {
        object([
            "type": .string("tool-call"),
            "toolCallId": .string(staticCall.toolCallId),
            "toolName": .string(staticCall.toolName),
            "input": staticCall.input,
            "providerExecuted": optionalBool(staticCall.providerExecuted),
            "providerMetadata": encodedProviderMetadata(staticCall.providerMetadata),
            "dynamic": optionalBool(staticCall.dynamic),
            "invalid": optionalBool(staticCall.invalid)
        ])
    }

    private static func toolCall(dynamicCall: DynamicToolCall) -> JSONValue {
        var map: [String: JSONValue] = [
            "type": .string("tool-call"),
            "toolCallId": .string(dynamicCall.toolCallId),
            "toolName": .string(dynamicCall.toolName),
            "input": dynamicCall.input,
            "dynamic": .bool(true)
        ]
        if let providerExecuted = dynamicCall.providerExecuted {
            map["providerExecuted"] = .bool(providerExecuted)
        }
        if let metadata = encodedProviderMetadata(dynamicCall.providerMetadata) {
            map["providerMetadata"] = metadata
        }
        if let invalid = dynamicCall.invalid {
            map["invalid"] = .bool(invalid)
        }
        if let error = dynamicCall.error {
            map["error"] = .string(String(describing: error))
        }
        return .object(map)
    }

    private static func toolResult(_ result: TypedToolResult) -> JSONValue {
        switch result {
        case .static(let staticResult):
            return toolResult(staticResult: staticResult)
        case .dynamic(let dynamicResult):
            return toolResult(dynamicResult: dynamicResult)
        }
    }

    private static func toolResult(staticResult: StaticToolResult) -> JSONValue {
        object([
            "type": .string("tool-result"),
            "toolCallId": .string(staticResult.toolCallId),
            "toolName": .string(staticResult.toolName),
            "input": staticResult.input,
            "output": staticResult.output,
            "providerExecuted": optionalBool(staticResult.providerExecuted),
            "preliminary": optionalBool(staticResult.preliminary),
            "providerMetadata": encodedProviderMetadata(staticResult.providerMetadata)
        ])
    }

    private static func toolResult(dynamicResult: DynamicToolResult) -> JSONValue {
        object([
            "type": .string("tool-result"),
            "toolCallId": .string(dynamicResult.toolCallId),
            "toolName": .string(dynamicResult.toolName),
            "input": dynamicResult.input,
            "output": dynamicResult.output,
            "providerExecuted": optionalBool(dynamicResult.providerExecuted),
            "preliminary": optionalBool(dynamicResult.preliminary),
            "providerMetadata": encodedProviderMetadata(dynamicResult.providerMetadata)
        ])
    }

    private static func toolError(_ error: TypedToolError) -> JSONValue {
        switch error {
        case .static(let staticError):
            return toolError(
                toolCallId: staticError.toolCallId,
                toolName: staticError.toolName,
                input: staticError.input,
                providerExecuted: staticError.providerExecuted,
                description: String(describing: staticError.error)
            )
        case .dynamic(let dynamicError):
            return toolError(
                toolCallId: dynamicError.toolCallId,
                toolName: dynamicError.toolName,
                input: dynamicError.input,
                providerExecuted: dynamicError.providerExecuted,
                description: String(describing: dynamicError.error)
            )
        }
    }

    private static func toolError(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerExecuted: Bool?,
        description: String
    ) -> JSONValue {
        var map: [String: JSONValue] = [
            "type": .string("tool-error"),
            "toolCallId": .string(toolCallId),
            "toolName": .string(toolName),
            "input": input,
            "error": .string(description)
        ]
        if let providerExecuted = providerExecuted {
            map["providerExecuted"] = .bool(providerExecuted)
        }
        return .object(map)
    }

    private static func toolApprovalRequest(_ request: ToolApprovalRequestOutput) -> JSONValue {
        object([
            "type": .string("tool-approval-request"),
            "approvalId": .string(request.approvalId),
            "toolCall": toolCall(request.toolCall)
        ])
    }

    // MARK: - Request / Response

    private static func request(_ metadata: LanguageModelRequestMetadata) -> JSONValue {
        object([
            "body": metadata.body ?? .null
        ])
    }

    private static func response(_ response: StepResultResponse) -> JSONValue {
        var map: [String: JSONValue] = [
            "id": .string(response.id),
            "timestamp": .string(isoString(from: response.timestamp)),
            "modelId": .string(response.modelId),
            "messages": .array(response.messages.map(responseMessage))
        ]
        if let headers = response.headers {
            map["headers"] = .object(headers.mapValues(JSONValue.string))
        }
        if let body = response.body {
            map["body"] = body
        }
        return .object(map)
    }

    private static func responseMessage(_ message: ResponseMessage) -> JSONValue {
        switch message {
        case .assistant(let assistant):
            var map: [String: JSONValue] = [
                "type": .string("assistant"),
                "content": assistantContent(assistant.content)
            ]
            if let options = encodedProviderOptions(assistant.providerOptions) {
                map["providerOptions"] = options
            }
            return .object(map)
        case .tool(let tool):
            var map: [String: JSONValue] = [
                "type": .string("tool"),
                "content": .array(tool.content.map(toolContentPart))
            ]
            if let options = encodedProviderOptions(tool.providerOptions) {
                map["providerOptions"] = options
            }
            return .object(map)
        }
    }

    private static func assistantContent(_ content: AssistantContent) -> JSONValue {
        switch content {
        case .text(let text):
            return object([
                "kind": .string("text"),
                "text": .string(text)
            ])
        case .parts(let parts):
            return object([
                "kind": .string("parts"),
                "parts": .array(parts.map(assistantContentPart))
            ])
        }
    }

    private static func assistantContentPart(_ part: AssistantContentPart) -> JSONValue {
        switch part {
        case .text(let textPart):
            return object([
                "type": .string("text"),
                "text": .string(textPart.text),
                "providerOptions": encodedProviderOptions(textPart.providerOptions)
            ])
        case .file(let filePart):
            return object([
                "type": .string("file"),
                "mediaType": .string(filePart.mediaType),
                "data": dataContent(filePart.data),
                "filename": optionalString(filePart.filename),
                "providerOptions": encodedProviderOptions(filePart.providerOptions)
            ])
        case .reasoning(let reasoningPart):
            return object([
                "type": .string("reasoning"),
                "text": .string(reasoningPart.text),
                "providerOptions": encodedProviderOptions(reasoningPart.providerOptions)
            ])
        case .toolCall(let callPart):
            return object([
                "type": .string("tool-call"),
                "toolCallId": .string(callPart.toolCallId),
                "toolName": .string(callPart.toolName),
                "input": callPart.input,
                "providerExecuted": optionalBool(callPart.providerExecuted),
                "providerOptions": encodedProviderOptions(callPart.providerOptions)
            ])
        case .toolResult(let resultPart):
            return object([
                "type": .string("tool-result"),
                "toolCallId": .string(resultPart.toolCallId),
                "toolName": .string(resultPart.toolName),
                "output": toolResultOutput(resultPart.output),
                "providerOptions": encodedProviderOptions(resultPart.providerOptions)
            ])
        case .toolApprovalRequest(let approvalPart):
            return object([
                "type": .string("tool-approval-request"),
                "approvalId": .string(approvalPart.approvalId),
                "toolCallId": .string(approvalPart.toolCallId)
            ])
        }
    }

    private static func toolContentPart(_ part: ToolContentPart) -> JSONValue {
        switch part {
        case .toolResult(let resultPart):
            return object([
                "type": .string("tool-result"),
                "toolCallId": .string(resultPart.toolCallId),
                "toolName": .string(resultPart.toolName),
                "output": toolResultOutput(resultPart.output),
                "providerOptions": encodedProviderOptions(resultPart.providerOptions)
            ])
        case .toolApprovalResponse(let response):
            return object([
                "type": .string("tool-approval-response"),
                "approvalId": .string(response.approvalId),
                "approved": .bool(response.approved),
                "reason": optionalString(response.reason)
            ])
        }
    }

    // MARK: - Tool Result Output

    private static func toolResultOutput(_ output: LanguageModelV3ToolResultOutput) -> JSONValue {
        switch output {
        case .text(let value):
            return object([
                "type": .string("text"),
                "value": .string(value)
            ])
        case .json(let value):
            return object([
                "type": .string("json"),
                "value": value
            ])
        case .executionDenied(let reason):
            return object([
                "type": .string("execution-denied"),
                "reason": optionalString(reason)
            ])
        case .errorText(let value):
            return object([
                "type": .string("error-text"),
                "value": .string(value)
            ])
        case .errorJson(let value):
            return object([
                "type": .string("error-json"),
                "value": value
            ])
        case .content(let parts):
            return object([
                "type": .string("content"),
                "value": .array(parts.map(toolResultContentPart))
            ])
        }
    }

    private static func toolResultContentPart(_ part: LanguageModelV3ToolResultContentPart) -> JSONValue {
        switch part {
        case .text(let text):
            return object([
                "type": .string("text"),
                "text": .string(text)
            ])
        case .media(let data, let mediaType):
            return object([
                "type": .string("image-data"),
                "data": .string(data),
                "mediaType": .string(mediaType)
            ])
        }
    }

    // MARK: - Misc Helpers

    private static func usage(_ usage: LanguageModelUsage) -> JSONValue {
        object([
            "inputTokens": optionalInt(usage.inputTokens),
            "outputTokens": optionalInt(usage.outputTokens),
            "totalTokens": optionalInt(usage.totalTokens),
            "reasoningTokens": optionalInt(usage.reasoningTokens),
            "cachedInputTokens": optionalInt(usage.cachedInputTokens)
        ])
    }

    private static func warnings(_ warnings: [CallWarning]?) -> JSONValue {
        guard let warnings else { return .null }
        return .array(warnings.map(warning))
    }

    private static func warning(_ warning: CallWarning) -> JSONValue {
        switch warning {
        case .unsupportedSetting(let setting, let details):
            return object([
                "type": .string("unsupported-setting"),
                "setting": .string(setting),
                "details": optionalString(details)
            ])
        case .unsupportedTool(let tool, let details):
            return object([
                "type": .string("unsupported-tool"),
                "tool": jsonValue(from: tool) ?? .null,
                "details": optionalString(details)
            ])
        case .other(let message):
            return object([
                "type": .string("other"),
                "message": .string(message)
            ])
        }
    }

    private static func encodedProviderMetadata(_ metadata: ProviderMetadata?) -> JSONValue? {
        guard let metadata else { return nil }
        return .object(metadata.mapValues(JSONValue.object))
    }

    private static func encodedProviderOptions(_ options: ProviderOptions?) -> JSONValue? {
        guard let options else { return nil }
        return .object(options.mapValues(JSONValue.object))
    }

    private static func dataContent(_ content: DataContentOrURL) -> JSONValue {
        switch content {
        case .data(let data):
            return object([
                "kind": .string("data"),
                "base64": .string(data.base64EncodedString())
            ])
        case .string(let string):
            return object([
                "kind": .string("string"),
                "value": .string(string)
            ])
        case .url(let url):
            return object([
                "kind": .string("url"),
                "value": .string(url.absoluteString)
            ])
        }
    }

    private static func merge(_ value: JSONValue, providerMetadata: ProviderMetadata?) -> JSONValue {
        guard case .object(var map) = value else { return value }
        if let metadata = encodedProviderMetadata(providerMetadata) {
            map["providerMetadata"] = metadata
        }
        return .object(map)
    }

    private static func object(_ entries: [String: JSONValue?]) -> JSONValue {
        var filtered: [String: JSONValue] = [:]
        for (key, value) in entries {
            if let value {
                filtered[key] = value
            }
        }
        return .object(filtered)
    }

    private static func optionalString(_ value: String?) -> JSONValue? {
        value.map(JSONValue.string)
    }

    private static func optionalInt(_ value: Int?) -> JSONValue? {
        value.map { .number(Double($0)) }
    }

    private static func optionalBool(_ value: Bool?) -> JSONValue? {
        value.map(JSONValue.bool)
    }

    private static func jsonValue<T: Encodable>(from value: T) -> JSONValue? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
            let jsonValue = JSONValue(jsonObject: jsonObject)
        else {
            return nil
        }
        return jsonValue
    }
}

// MARK: - JSONValue convenience initialiser

private extension JSONValue {
    init?(jsonObject any: Any) {
        switch any {
        case let dictionary as [String: Any]:
            var map: [String: JSONValue] = [:]
            for (key, value) in dictionary {
                guard let jsonValue = JSONValue(jsonObject: value) else { return nil }
                map[key] = jsonValue
            }
            self = .object(map)
        case let array as [Any]:
            var values: [JSONValue] = []
            values.reserveCapacity(array.count)
            for value in array {
                guard let jsonValue = JSONValue(jsonObject: value) else { return nil }
                values.append(jsonValue)
            }
            self = .array(values)
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case _ as NSNull:
            self = .null
        default:
            return nil
        }
    }
}

private func isoString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private extension JSONValue {
    func toJSONObject() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let values): return values.map { $0.toJSONObject() }
        case .object(let map): return map.mapValues { $0.toJSONObject() }
        }
    }

    func toJSONData(prettyPrinted: Bool, sortedKeys: Bool) throws -> Data {
        var options: JSONSerialization.WritingOptions = []
        if prettyPrinted { options.insert(.prettyPrinted) }
        if sortedKeys { options.insert(.sortedKeys) }
        let object = toJSONObject()
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    func toJSONString(prettyPrinted: Bool, sortedKeys: Bool) throws -> String {
        let data = try toJSONData(prettyPrinted: prettyPrinted, sortedKeys: sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }
}

