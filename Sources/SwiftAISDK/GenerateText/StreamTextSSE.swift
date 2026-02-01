import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Creates a Server-Sent Events (SSE) stream from a StreamText full stream.
///
/// Each emitted string already contains the `data:` prefix and terminating blank line (`\n\n`).
/// The payload mirrors the upstream `stream-text.ts` SSE framing with a subset of event types
/// that are currently required by the Swift SDK.
public func makeStreamTextSSEStream(
    from stream: AsyncThrowingStream<TextStreamPart, Error>,
    includeUsage: Bool = true
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            let encoder = StreamTextSSEEncoder(includeUsage: includeUsage)
            do {
                for try await part in stream {
                    let payloads = encoder.encode(part: part)
                    for payload in payloads {
                        continuation.yield(payload)
                    }
                }
                for payload in encoder.finalize() {
                    continuation.yield(payload)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

private final class StreamTextSSEEncoder {
    private var includeUsage: Bool
    private var finishedEmitted = false
    private let jsonEncoder: JSONEncoder

    init(includeUsage: Bool) {
        self.includeUsage = includeUsage
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.jsonEncoder = enc
    }

    func encode(part: TextStreamPart) -> [String] {
        switch part {
        case .start:
            return [encode(event: ["type": "start"])]

        case let .startStep(request, warnings):
            var payload: [String: Any] = ["type": "start-step"]
            if let body = request.body {
                payload["request"] = ["body": toJSONAny(body)]
            }
            if !warnings.isEmpty {
                if let data = try? jsonEncoder.encode(warnings),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                    payload["warnings"] = array
                }
            }
            return [encode(event: payload)]

        case let .finishStep(response, usage, finishReason, metadata):
            var payload: [String: Any] = [
                "type": "finish-step",
                "finishReason": finishReason.rawValue,
                "usage": usageDictionary(usage)
            ]
            if let responseData = try? jsonEncoder.encode(response),
               let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                payload["response"] = json
            }
            if let meta = providerMetadataDictionary(metadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case .abort:
            finishedEmitted = true
            return [encode(event: ["type": "abort"])]

        case let .textStart(id, providerMetadata):
            var payload: [String: Any] = ["type": "text-start", "id": id]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .textDelta(id, delta, providerMetadata):
            var payload: [String: Any] = ["type": "text-delta", "id": id, "delta": delta]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .textEnd(id, providerMetadata):
            var payload: [String: Any] = ["type": "text-end", "id": id]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .reasoningStart(id, providerMetadata):
            var payload: [String: Any] = ["type": "reasoning-start", "id": id]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .reasoningEnd(id, providerMetadata):
            var payload: [String: Any] = ["type": "reasoning-end", "id": id]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .reasoningDelta(id, text, providerMetadata):
            var payload: [String: Any] = ["type": "reasoning-delta", "id": id, "delta": text]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .toolCall(call):
            return encodeToolCall(call)

        case let .toolResult(result):
            return encodeToolResult(result)

        case let .toolInputStart(id, toolName, providerMetadata, executed, dynamicFlag, title):
            var payload: [String: Any] = ["type": "tool-input-start", "id": id, "name": toolName]
            if let executed { payload["providerExecuted"] = executed }
            if let dynamicFlag { payload["dynamic"] = dynamicFlag }
            if let title { payload["title"] = title }
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .toolInputDelta(id, delta, providerMetadata):
            var payload: [String: Any] = ["type": "tool-input-delta", "id": id, "delta": delta]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .toolInputEnd(id, providerMetadata):
            var payload: [String: Any] = ["type": "tool-input-end", "id": id]
            if let meta = providerMetadataDictionary(providerMetadata) { payload["providerMetadata"] = meta }
            return [encode(event: payload)]

        case let .source(source):
            if let data = try? jsonEncoder.encode(source),
               var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Ensure type field stays 'source' per upstream shape
                obj["type"] = "source"
                return [encode(event: obj)]
            }
            return []

        case let .file(file):
            var payload: [String: Any] = [
                "type": "file",
                "base64": file.base64,
                "mediaType": file.mediaType
            ]
            return [encode(event: payload)]

        case let .toolError(error):
            var payload: [String: Any] = [
                "type": "tool-error",
                "toolCallId": error.toolCallId,
                "toolName": error.toolName,
            ]
            // Serialize error as string description to keep payload lightweight
            payload["error"] = String(describing: error.error)
            if let executed = error.providerExecuted { payload["providerExecuted"] = executed }
            payload["input"] = toJSONAny(error.input)
            if error.isDynamic { payload["dynamic"] = true }
            return [encode(event: payload)]

        case let .toolOutputDenied(denied):
            var payload: [String: Any] = [
                "type": "tool-output-denied",
                "toolCallId": denied.toolCallId,
                "toolName": denied.toolName
            ]
            if let executed = denied.providerExecuted { payload["providerExecuted"] = executed }
            return [encode(event: payload)]

        case let .toolApprovalRequest(request):
            var payload: [String: Any] = [
                "type": "tool-approval-request",
                "approvalId": request.approvalId,
            ]
            // Inline basic info of the tool call for convenience
            payload["toolCallId"] = request.toolCall.toolCallId
            payload["toolName"] = request.toolCall.toolName
            payload["input"] = toJSONAny(request.toolCall.input)
            if let executed = request.toolCall.providerExecuted { payload["providerExecuted"] = executed }
            if let meta = providerMetadataDictionary(request.toolCall.providerMetadata) {
                payload["providerMetadata"] = meta
            }
            if case .dynamic = request.toolCall { payload["dynamic"] = true }
            return [encode(event: payload)]

        case let .finish(finishReason, usage):
            finishedEmitted = true
            var payload: [String: Any] = ["type": "finish", "finishReason": finishReason.rawValue]
            if includeUsage {
                payload["usage"] = usageDictionary(usage)
            }
            return [encode(event: payload)]
        case .raw:
            return []

        case let .error(error):
            let description: String
            if let localized = error as? LocalizedError, let failure = localized.errorDescription {
                description = failure
            } else {
                description = String(describing: error)
            }
            return [encode(event: ["type": "error", "message": description])]
        }
    }

    func finalize() -> [String] {
        finishedEmitted ? [] : [encode(event: ["type": "end"])]
    }

    private func encodeToolCall(_ call: TypedToolCall) -> [String] {
        switch call {
        case .static(let value):
            var payload: [String: Any] = [
                "type": "tool-call",
                "toolCallId": value.toolCallId,
                "toolName": value.toolName,
                "input": toJSONAny(value.input)
            ]
            if let metadata = value.providerMetadata { payload["providerMetadata"] = metadata }
            if let executed = value.providerExecuted { payload["providerExecuted"] = executed }
            if let invalid = value.invalid { payload["invalid"] = invalid }
            return [encode(event: payload)]
        case .dynamic(let value):
            var payload: [String: Any] = [
                "type": "tool-call",
                "toolCallId": value.toolCallId,
                "toolName": value.toolName,
                "input": toJSONAny(value.input)
            ]
            if let metadata = value.providerMetadata { payload["providerMetadata"] = metadata }
            if let executed = value.providerExecuted { payload["providerExecuted"] = executed }
            if let invalid = value.invalid { payload["invalid"] = invalid }
            if let error = value.error { payload["error"] = error }
            return [encode(event: payload)]
        }
    }

    private func encodeToolResult(_ result: TypedToolResult) -> [String] {
        switch result {
        case .static(let value):
            var payload: [String: Any] = [
                "type": "tool-result",
                "toolCallId": value.toolCallId,
                "toolName": value.toolName,
                "result": toJSONAny(value.output),
                "input": toJSONAny(value.input)
            ]
            if let metadata = providerMetadataDictionary(value.providerMetadata) { payload["providerMetadata"] = metadata }
            if let executed = value.providerExecuted { payload["providerExecuted"] = executed }
            if let prelim = value.preliminary { payload["preliminary"] = prelim }
            return [encode(event: payload)]
        case .dynamic(let value):
            var payload: [String: Any] = [
                "type": "tool-result",
                "toolCallId": value.toolCallId,
                "toolName": value.toolName,
                "result": toJSONAny(value.output),
                "input": toJSONAny(value.input)
            ]
            if let metadata = providerMetadataDictionary(value.providerMetadata) { payload["providerMetadata"] = metadata }
            if let executed = value.providerExecuted { payload["providerExecuted"] = executed }
            if let preliminary = value.preliminary { payload["preliminary"] = preliminary }
            payload["dynamic"] = true
            return [encode(event: payload)]
        }
    }

    private func usageDictionary(_ usage: LanguageModelUsage) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let input = usage.inputTokens { dict["inputTokens"] = input }
        if let output = usage.outputTokens { dict["outputTokens"] = output }
        if let total = usage.totalTokens { dict["totalTokens"] = total }
        if let reasoning = usage.reasoningTokens { dict["reasoningTokens"] = reasoning }
        if let cached = usage.cachedInputTokens { dict["cachedInputTokens"] = cached }
        return dict
    }

    private func providerMetadataDictionary(_ metadata: ProviderMetadata?) -> [String: Any]? {
        guard let metadata else { return nil }
        var result: [String: Any] = [:]
        for (provider, values) in metadata {
            var obj: [String: Any] = [:]
            for (k, v) in values { obj[k] = toJSONAny(v) }
            result[provider] = obj
        }
        return result
    }

    private func encode(event payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "data: {}\n\n"
        }
        return "data: \(json)\n\n"
    }

    // Convert JSONValue to JSON-serializable Any
    private func toJSONAny(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let arr): return arr.map { toJSONAny($0) }
        case .object(let dict):
            var obj: [String: Any] = [:]
            for (k, v) in dict { obj[k] = toJSONAny(v) }
            return obj
        }
    }
}
