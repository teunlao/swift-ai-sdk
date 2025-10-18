import Foundation
import AISDKProvider
import AISDKProviderUtils

/// High-level event emitted while observing a StreamText V2 full stream.
public enum StreamTextV2Event: Sendable {
    case start
    case startStep(index: Int, warnings: [LanguageModelV3CallWarning])
    case textDelta(text: String, id: String)
    case textEnd(id: String)
    case reasoningDelta(text: String, id: String)
    case toolCall(TypedToolCall)
    case toolResult(TypedToolResult)
    case toolError(TypedToolError)
    case toolApprovalRequest(ToolApprovalRequestOutput)
    case toolOutputDenied(ToolOutputDenied)
    case source(Source)
    case file(GeneratedFile)
    case finish(reason: FinishReason, usage: LanguageModelUsage)
    case abort
}

/// Converts a `TextStreamPart` stream into a higher-level event stream mirroring the
/// upstream `stream-text.ts` event helpers.
public func makeStreamTextV2EventStream(
    from stream: AsyncThrowingStream<TextStreamPart, Error>
) -> AsyncThrowingStream<StreamTextV2Event, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            let encoder = StreamTextV2EventEncoder()
            do {
                for try await part in stream {
                    if Task.isCancelled { break }
                    for event in encoder.encode(part: part) {
                        continuation.yield(event)
                    }
                }
                for event in encoder.finalize() {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Summary produced by `summarizeStreamTextV2Events`.
public struct StreamTextV2EventSummary: Sendable {
    public var text: String
    public var reasoning: [String]
    public var toolCalls: [TypedToolCall]
    public var toolResults: [TypedToolResult]
    public var files: [GeneratedFile]
    public var sources: [Source]
    public var finishReason: FinishReason?
    public var usage: LanguageModelUsage?
    public var aborted: Bool

    public init(
        text: String = "",
        reasoning: [String] = [],
        toolCalls: [TypedToolCall] = [],
        toolResults: [TypedToolResult] = [],
        files: [GeneratedFile] = [],
        sources: [Source] = [],
        finishReason: FinishReason? = nil,
        usage: LanguageModelUsage? = nil,
        aborted: Bool = false
    ) {
        self.text = text
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.files = files
        self.sources = sources
        self.finishReason = finishReason
        self.usage = usage
        self.aborted = aborted
    }
}

/// Consumes a StreamText V2 event stream and aggregates high-level data.
public func summarizeStreamTextV2Events(
    _ stream: AsyncThrowingStream<StreamTextV2Event, Error>
) async throws -> StreamTextV2EventSummary {
    var summary = StreamTextV2EventSummary()
    for try await event in stream {
        switch event {
        case .start:
            continue
        case .startStep:
            continue
        case let .textDelta(text, _):
            summary.text.append(contentsOf: text)
        case .textEnd:
            continue
        case let .reasoningDelta(text, _):
            summary.reasoning.append(text)
        case let .toolCall(call):
            summary.toolCalls.append(call)
        case let .toolResult(result):
            summary.toolResults.append(result)
        case .toolError:
            continue
        case .toolApprovalRequest:
            continue
        case .toolOutputDenied:
            continue
        case let .source(source):
            summary.sources.append(source)
        case let .file(file):
            summary.files.append(file)
        case let .finish(reason, usage):
            summary.finishReason = reason
            summary.usage = usage
        case .abort:
            summary.aborted = true
        }
    }
    return summary
}

// MARK: - Internal encoder

private final class StreamTextV2EventEncoder {
    private var currentStep = -1
    private var finishedEmitted = false

    func encode(part: TextStreamPart) -> [StreamTextV2Event] {
        switch part {
        case .start:
            currentStep = -1
            finishedEmitted = false
            return [.start]

        case let .startStep(_, warnings):
            currentStep += 1
            return [.startStep(index: currentStep, warnings: warnings)]

        case .textStart:
            return []

        case let .textDelta(id, text, _):
            return [.textDelta(text: text, id: id)]

        case let .textEnd(id, _):
            return [.textEnd(id: id)]

        case let .reasoningDelta(id, text, _):
            return [.reasoningDelta(text: text, id: id)]

        case let .toolCall(call):
            return [.toolCall(call)]

        case let .toolResult(result):
            return [.toolResult(result)]

        case let .toolError(error):
            return [.toolError(error)]

        case let .toolApprovalRequest(request):
            return [.toolApprovalRequest(request)]

        case let .toolOutputDenied(denied):
            return [.toolOutputDenied(denied)]

        case let .source(source):
            return [.source(source)]

        case let .file(file):
            return [.file(file)]

        case let .finishStep:
            return []

        case let .finish(reason, usage):
            finishedEmitted = true
            return [.finish(reason: reason, usage: usage)]

        case .abort:
            finishedEmitted = true
            return [.abort]

        case .raw:
            return []

        case .error:
            return []

        case .toolInputStart, .toolInputDelta, .toolInputEnd,
             .reasoningStart, .reasoningEnd:
            return []
        }
    }

    func finalize() -> [StreamTextV2Event] {
        finishedEmitted ? [] : [.finish(reason: .unknown, usage: LanguageModelUsage())]
    }
}
