import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIResponsesLanguageModelV4: LanguageModelV4, @unchecked Sendable {
    public let specificationVersion = "v4"

    private let modelIdentifier: OpenAIResponsesModelId
    private let config: OpenAIConfig
    private let providerOptionsName: String
    private let v3Model: OpenAIResponsesLanguageModel

    public init(modelId: OpenAIResponsesModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.providerOptionsName = config.provider.contains("azure") ? "azure" : "openai"
        self.v3Model = OpenAIResponsesLanguageModel(modelId: modelId, config: config)
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await v3Model.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let v3Options = try convertOpenAIResponsesV4CallOptionsToV3(
            options,
            providerOptionsName: providerOptionsName
        )
        let result = try await v3Model.doGenerate(options: v3Options)
        return try convertLanguageModelV3GenerateResultToV4(result)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let v3Options = try convertOpenAIResponsesV4CallOptionsToV3(
            options,
            providerOptionsName: providerOptionsName
        )
        let result = try await v3Model.doStream(options: v3Options)
        let url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses"))
        let checkedStream = try await throwIfOpenAIResponsesStreamErrorBeforeOutput(
            stream: result.stream,
            url: url,
            requestBodyValues: result.request?.body,
            responseHeaders: result.response?.headers
        )

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in checkedStream {
                        continuation.yield(try convertLanguageModelV3StreamPartToV4(part))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return LanguageModelV4StreamResult(
            stream: stream,
            request: result.request.map { LanguageModelV4RequestInfo(body: $0.body) },
            response: result.response.map { LanguageModelV4StreamResponseInfo(headers: $0.headers) }
        )
    }
}

private func convertOpenAIResponsesV4CallOptionsToV3(
    _ options: LanguageModelV4CallOptions,
    providerOptionsName: String
) throws -> LanguageModelV3CallOptions {
    LanguageModelV3CallOptions(
        prompt: try options.prompt.map { try convertOpenAIResponsesV4MessageToV3($0, providerOptionsName: providerOptionsName) },
        maxOutputTokens: options.maxOutputTokens,
        temperature: options.temperature,
        stopSequences: options.stopSequences,
        topP: options.topP,
        topK: options.topK,
        presencePenalty: options.presencePenalty,
        frequencyPenalty: options.frequencyPenalty,
        responseFormat: options.responseFormat.map(convertOpenAIResponsesV4ResponseFormatToV3),
        seed: options.seed,
        tools: try options.tools?.map(convertOpenAIResponsesV4ToolToV3),
        toolChoice: options.toolChoice.map(convertOpenAIResponsesV4ToolChoiceToV3),
        includeRawChunks: options.includeRawChunks,
        abortSignal: options.abortSignal,
        headers: options.headers,
        providerOptions: mergeOpenAIResponsesV4Reasoning(
            reasoning: options.reasoning,
            providerOptions: options.providerOptions,
            providerOptionsName: providerOptionsName
        )
    )
}

private func mergeOpenAIResponsesV4Reasoning(
    reasoning: LanguageModelV4ReasoningEffort?,
    providerOptions: SharedV4ProviderOptions?,
    providerOptionsName: String
) -> SharedV3ProviderOptions? {
    let targetProvider = providerOptions?[providerOptionsName] != nil || providerOptionsName == "openai"
        ? providerOptionsName
        : (providerOptions?["openai"] != nil ? "openai" : providerOptionsName)

    var merged = providerOptions ?? [:]
    var targetOptions = merged[targetProvider] ?? [:]
    let providerEffort = targetOptions["reasoningEffort"]?.stringValue
    let resolvedEffort = providerEffort ?? (isCustomReasoning(reasoning) ? reasoning?.rawValue : nil)

    guard let resolvedEffort else {
        return providerOptions
    }

    if targetOptions["reasoningEffort"] == nil {
        targetOptions["reasoningEffort"] = .string(resolvedEffort)
    }
    if targetOptions["reasoningSummary"] == nil, resolvedEffort != "none" {
        targetOptions["reasoningSummary"] = .string("detailed")
    }

    merged[targetProvider] = targetOptions
    return merged
}

private func convertOpenAIResponsesV4ResponseFormatToV3(
    _ value: LanguageModelV4ResponseFormat
) -> LanguageModelV3ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

private func convertOpenAIResponsesV4ToolChoiceToV3(_ value: LanguageModelV4ToolChoice) -> LanguageModelV3ToolChoice {
    switch value {
    case .auto:
        return .auto
    case .none:
        return .none
    case .required:
        return .required
    case .tool(let toolName):
        return .tool(toolName: toolName)
    }
}

private func convertOpenAIResponsesV4ToolToV3(_ value: LanguageModelV4Tool) throws -> LanguageModelV3Tool {
    switch value {
    case .function(let tool):
        return .function(LanguageModelV3FunctionTool(
            name: tool.name,
            inputSchema: tool.inputSchema,
            inputExamples: tool.inputExamples?.map { LanguageModelV3ToolInputExample(input: $0.input) },
            description: tool.description,
            strict: tool.strict,
            providerOptions: tool.providerOptions
        ))
    case .provider(let tool):
        return .provider(LanguageModelV3ProviderTool(id: tool.id, name: tool.name, args: tool.args))
    }
}

private func convertOpenAIResponsesV4MessageToV3(
    _ value: LanguageModelV4Message,
    providerOptionsName: String
) throws -> LanguageModelV3Message {
    switch value {
    case let .system(content, providerOptions):
        return .system(content: content, providerOptions: providerOptions)
    case let .user(content, providerOptions):
        return .user(
            content: try content.map { try convertOpenAIResponsesV4UserMessagePartToV3($0, providerOptionsName: providerOptionsName) },
            providerOptions: providerOptions
        )
    case let .assistant(content, providerOptions):
        return .assistant(
            content: try content.compactMap { try convertOpenAIResponsesV4MessagePartToV3($0, providerOptionsName: providerOptionsName) },
            providerOptions: providerOptions
        )
    case let .tool(content, providerOptions):
        return .tool(
            content: try content.map { try convertOpenAIResponsesV4ToolMessagePartToV3($0, providerOptionsName: providerOptionsName) },
            providerOptions: providerOptions
        )
    }
}

private func convertOpenAIResponsesV4UserMessagePartToV3(
    _ value: LanguageModelV4UserMessagePart,
    providerOptionsName: String
) throws -> LanguageModelV3UserMessagePart {
    switch value {
    case .text(let part):
        return .text(LanguageModelV3TextPart(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        return .file(LanguageModelV3FilePart(
            data: try convertOpenAIResponsesV4FileDataToV3(part.data, providerOptionsName: providerOptionsName),
            mediaType: part.mediaType,
            filename: part.filename,
            providerOptions: part.providerOptions
        ))
    }
}

private func convertOpenAIResponsesV4MessagePartToV3(
    _ value: LanguageModelV4MessagePart,
    providerOptionsName: String
) throws -> LanguageModelV3MessagePart? {
    switch value {
    case .text(let part):
        return .text(LanguageModelV3TextPart(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        return .file(LanguageModelV3FilePart(
            data: try convertOpenAIResponsesV4FileDataToV3(part.data, providerOptionsName: providerOptionsName),
            mediaType: part.mediaType,
            filename: part.filename,
            providerOptions: part.providerOptions
        ))
    case .reasoning(let part):
        return .reasoning(LanguageModelV3ReasoningPart(text: part.text, providerOptions: part.providerOptions))
    case .toolCall(let part):
        return .toolCall(LanguageModelV3ToolCallPart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            input: part.input,
            providerExecuted: part.providerExecuted,
            providerOptions: part.providerOptions
        ))
    case .toolResult(let part):
        return .toolResult(LanguageModelV3ToolResultPart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            output: try convertOpenAIResponsesV4ToolResultOutputToV3(part.output, providerOptionsName: providerOptionsName),
            providerOptions: part.providerOptions
        ))
    case .custom(let part):
        if part.kind == "openai.compaction" {
            return .custom(LanguageModelV3CustomPart(kind: part.kind, providerOptions: part.providerOptions))
        }
        throw UnsupportedFunctionalityError(functionality: "language model v4 custom prompt part kind \(part.kind) on OpenAI Responses")
    case .reasoningFile:
        throw UnsupportedFunctionalityError(functionality: "language model v4 reasoning-file prompt parts on OpenAI Responses")
    }
}

private func convertOpenAIResponsesV4ToolMessagePartToV3(
    _ value: LanguageModelV4ToolMessagePart,
    providerOptionsName: String
) throws -> LanguageModelV3ToolMessagePart {
    switch value {
    case .toolResult(let part):
        return .toolResult(LanguageModelV3ToolResultPart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            output: try convertOpenAIResponsesV4ToolResultOutputToV3(part.output, providerOptionsName: providerOptionsName),
            providerOptions: part.providerOptions
        ))
    case .toolApprovalResponse(let part):
        return .toolApprovalResponse(LanguageModelV3ToolApprovalResponsePart(
            approvalId: part.approvalId,
            approved: part.approved,
            reason: part.reason,
            providerOptions: part.providerOptions
        ))
    }
}

private func convertOpenAIResponsesV4ToolResultOutputToV3(
    _ value: LanguageModelV4ToolResultOutput,
    providerOptionsName: String
) throws -> LanguageModelV3ToolResultOutput {
    switch value {
    case let .text(value, providerOptions):
        return .text(value: value, providerOptions: providerOptions)
    case let .json(value, providerOptions):
        return .json(value: value, providerOptions: providerOptions)
    case let .executionDenied(reason, providerOptions):
        return .executionDenied(reason: reason, providerOptions: providerOptions)
    case let .errorText(value, providerOptions):
        return .errorText(value: value, providerOptions: providerOptions)
    case let .errorJson(value, providerOptions):
        return .errorJson(value: value, providerOptions: providerOptions)
    case .content(let value):
        return .content(
            value: try value.compactMap { try convertOpenAIResponsesV4ToolResultContentPartToV3($0, providerOptionsName: providerOptionsName) }
        )
    }
}

private func convertOpenAIResponsesV4ToolResultContentPartToV3(
    _ value: LanguageModelV4ToolResultContentPart,
    providerOptionsName: String
) throws -> LanguageModelV3ToolResultContentPart? {
    switch value {
    case let .text(text, _):
        return .text(text: text)
    case let .file(data, mediaType, _, _):
        return .media(
            data: try convertOpenAIResponsesV4FileDataToBase64String(data, providerOptionsName: providerOptionsName),
            mediaType: mediaType
        )
    case .custom:
        return nil
    }
}

private func convertOpenAIResponsesV4FileDataToV3(
    _ value: SharedV4FileData,
    providerOptionsName: String
) throws -> LanguageModelV3DataContent {
    switch value {
    case .data(let data):
        return .data(data)
    case .base64(let base64):
        return .base64(base64)
    case .url(let url):
        return .url(url)
    case .text:
        throw UnsupportedFunctionalityError(functionality: "text file parts")
    case .reference(let reference):
        return .base64(try resolveProviderReference(reference: reference, provider: providerOptionsName))
    }
}

private func convertOpenAIResponsesV4FileDataToBase64String(
    _ value: SharedV4FileData,
    providerOptionsName: String
) throws -> String {
    switch value {
    case .data(let data):
        return data.base64EncodedString()
    case .base64(let base64):
        return base64
    case .text(let text):
        return Data(text.utf8).base64EncodedString()
    case .url:
        throw UnsupportedFunctionalityError(functionality: "tool result file URLs on OpenAI Responses")
    case .reference(let reference):
        return try resolveProviderReference(reference: reference, provider: providerOptionsName)
    }
}

private func throwIfOpenAIResponsesStreamErrorBeforeOutput(
    stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
    url: String,
    requestBodyValues: Any?,
    responseHeaders: SharedV4Headers?
) async throws -> AsyncThrowingStream<LanguageModelV3StreamPart, Error> {
    let iteratorBox = OpenAIResponsesV3StreamIteratorBox(iterator: stream.makeAsyncIterator())
    var buffered: [LanguageModelV3StreamPart] = []

    while let part = try await iteratorBox.next() {
        if case .error(let errorValue) = part {
            throw openAIResponsesStreamError(
                error: errorValue,
                url: url,
                requestBodyValues: requestBodyValues,
                responseHeaders: responseHeaders
            )
        }

        buffered.append(part)
        if isOpenAIResponsesOutputPart(part) {
            return makeOpenAIResponsesCheckedV3Stream(buffered: buffered, iteratorBox: iteratorBox)
        }
    }

    return makeOpenAIResponsesCheckedV3Stream(buffered: buffered, iteratorBox: iteratorBox)
}

private final class OpenAIResponsesV3StreamIteratorBox: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Iterator

    init(iterator: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Iterator) {
        self.iterator = iterator
    }

    func next() async throws -> LanguageModelV3StreamPart? {
        try await iterator.next()
    }
}

private func makeOpenAIResponsesCheckedV3Stream(
    buffered: [LanguageModelV3StreamPart],
    iteratorBox: OpenAIResponsesV3StreamIteratorBox
) -> AsyncThrowingStream<LanguageModelV3StreamPart, Error> {
    AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            do {
                for part in buffered {
                    continuation.yield(part)
                }
                while let part = try await iteratorBox.next() {
                    continuation.yield(part)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}

private func isOpenAIResponsesOutputPart(_ part: LanguageModelV3StreamPart) -> Bool {
    switch part {
    case .streamStart, .raw, .responseMetadata:
        return false
    case .error:
        return false
    default:
        return true
    }
}

private func openAIResponsesStreamError(
    error: JSONValue,
    url: String,
    requestBodyValues: Any?,
    responseHeaders: SharedV4Headers?
) -> APICallError {
    let streamError = parseOpenAIResponsesStreamError(error)
    let message = streamError?.message ?? "OpenAI Responses stream error"
    let code = streamError?.code
    let type = streamError?.type

    return APICallError(
        message: message,
        url: url,
        requestBodyValues: requestBodyValues,
        statusCode: openAIResponsesStreamErrorStatusCode(code: code, type: type),
        responseHeaders: responseHeaders,
        responseBody: jsonString(from: error),
        data: error
    )
}

private struct OpenAIResponsesStreamErrorInfo {
    let message: String
    let code: JSONValue?
    let type: String?
}

private func parseOpenAIResponsesStreamError(_ error: JSONValue) -> OpenAIResponsesStreamErrorInfo? {
    guard let value = error.objectValue else {
        return nil
    }

    if value["type"]?.stringValue == "response.failed" {
        let responseError = value["response"]?.objectValue?["error"]?.objectValue
        guard let message = responseError?["message"]?.stringValue else {
            return nil
        }
        return OpenAIResponsesStreamErrorInfo(
            message: message,
            code: responseError?["code"],
            type: "response.failed"
        )
    }

    let nestedError = value["error"]?.objectValue
    let payload = nestedError ?? value
    guard let message = payload["message"]?.stringValue else {
        return nil
    }

    let hasRecognizableErrorShape = nestedError != nil
        || payload["type"]?.stringValue != nil
        || payload.keys.contains("code")
        || payload.keys.contains("param")

    guard hasRecognizableErrorShape else {
        return nil
    }

    return OpenAIResponsesStreamErrorInfo(
        message: message,
        code: payload["code"],
        type: payload["type"]?.stringValue
    )
}

private func openAIResponsesStreamErrorStatusCode(code: JSONValue?, type: String?) -> Int {
    if let code {
        switch code {
        case .number(let value):
            let intValue = Int(value)
            if Double(intValue) == value, (400...599).contains(intValue) {
                return intValue
            }
        case .string(let value):
            if value.range(of: #"^\d{3}$"#, options: .regularExpression) != nil,
               let intValue = Int(value),
               (400...599).contains(intValue) {
                return intValue
            }
        default:
            break
        }
    }

    let discriminator = [code?.stringValue, type]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

    if discriminator.contains("insufficient_quota") || discriminator.contains("rate_limit") {
        return 429
    }
    if discriminator.contains("authentication") { return 401 }
    if discriminator.contains("permission") { return 403 }
    if discriminator.contains("not_found") { return 404 }
    if discriminator.contains("invalid")
        || discriminator.contains("bad_request")
        || discriminator.contains("context_length") {
        return 400
    }
    if discriminator.contains("overload") { return 503 }
    if discriminator.contains("timeout") { return 504 }

    return 500
}

private func jsonString(from value: JSONValue) -> String? {
    do {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
