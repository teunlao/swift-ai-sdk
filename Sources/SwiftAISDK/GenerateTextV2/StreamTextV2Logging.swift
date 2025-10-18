import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Options that control how StreamText V2 events are logged.
public struct StreamTextV2LogOptions: Sendable {
    /// When `true`, each line is prefixed with an ISO8601 timestamp.
    public var includeTimestamps: Bool

    /// Optional prefix appended before each log line (after the timestamp when enabled).
    public var prefix: String?

    /// Clock used to obtain timestamps. Defaults to `Date.init`.
    public var clock: @Sendable () -> Date

    /// Formatter used to render timestamps.
    public var timestampFormatter: @Sendable (Date) -> String

    /// String appended after every line (default `\n`).
    public var lineTerminator: String

    public init(
        includeTimestamps: Bool = false,
        prefix: String? = nil,
        clock: @escaping @Sendable () -> Date = Date.init,
        timestampFormatter: @escaping @Sendable (Date) -> String = StreamTextV2LogOptions.defaultTimestampFormatter,
        lineTerminator: String = "\n"
    ) {
        self.includeTimestamps = includeTimestamps
        self.prefix = prefix
        self.clock = clock
        self.timestampFormatter = timestampFormatter
        self.lineTerminator = lineTerminator
    }
}

/// Creates a textual log stream from StreamText V2 parts.
///
/// Each produced string already contains a trailing terminator (default `\n`) so it can be
/// written directly to an output.
public func makeStreamTextV2LogStream(
    from stream: AsyncThrowingStream<TextStreamPart, Error>,
    options: StreamTextV2LogOptions = StreamTextV2LogOptions()
) -> AsyncThrowingStream<String, Error> {
    let eventStream = makeStreamTextV2EventStream(from: stream)
    return AsyncThrowingStream { continuation in
        let task = Task {
            let encoder = StreamTextV2LogEncoder(options: options)
            do {
                for try await event in eventStream {
                    for line in encoder.encode(event: event) {
                        continuation.yield(line)
                    }
                }
                for line in encoder.finalize() {
                    continuation.yield(line)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Iterates through the log stream and forwards each line into the provided callback.
public func logStreamTextV2Events(
    from stream: AsyncThrowingStream<TextStreamPart, Error>,
    options: StreamTextV2LogOptions = StreamTextV2LogOptions(),
    onLine: @escaping @Sendable (String) -> Void
) async throws {
    let logStream = makeStreamTextV2LogStream(from: stream, options: options)
    for try await line in logStream {
        onLine(line)
    }
}

// MARK: - Internal encoder

private final class StreamTextV2LogEncoder {
    private let options: StreamTextV2LogOptions
    private var currentStep: Int = -1

    init(options: StreamTextV2LogOptions) {
        self.options = options
    }

    func encode(event: StreamTextV2Event) -> [String] {
        var message: String
        switch event {
        case .start:
            currentStep = -1
            message = "stream:start"
        case let .startStep(index, warnings):
            currentStep = index
            var lines: [String] = [format("step \(index):start")]
            if !warnings.isEmpty {
                for warning in warnings {
                    lines.append(format("step \(index):warning \(warning.codeDescription())"))
                }
            }
            return lines
        case let .textDelta(text, id):
            message = "step \(currentStep):text[\(id)] += \(text)"
        case let .textEnd(id):
            message = "step \(currentStep):text[\(id)] end"
        case let .reasoningDelta(text, id):
            message = "step \(currentStep):reasoning[\(id)] += \(text)"
        case let .toolCall(call):
            message = "step \(currentStep):tool-call \(call.logDescription())"
        case let .toolResult(result):
            message = "step \(currentStep):tool-result \(result.logDescription())"
        case let .source(source):
            message = "source \(source.logDescription())"
        case let .file(file):
            message = "file \(file.logDescription())"
        case let .finish(reason, usage):
            let usageSummary = usage.logDescription()
            message = "stream:finish reason=\(reason.rawValue) \(usageSummary)"
        case .abort:
            message = "stream:abort"
        }
        return [format(message)]
    }

    func finalize() -> [String] {
        []
    }

    private func format(_ content: String) -> String {
        var components: [String] = []
        if options.includeTimestamps {
            let date = options.clock()
            let ts = options.timestampFormatter(date)
            components.append("[\(ts)]")
        }
        if let prefix = options.prefix, !prefix.isEmpty {
            components.append(prefix)
        }
        components.append(content)
        return components.joined(separator: " ") + options.lineTerminator
    }
}

// MARK: - Helpers

private extension LanguageModelV3CallWarning {
    func codeDescription() -> String {
        switch self {
        case let .unsupportedSetting(setting, details):
            if let details { return "unsupported-setting(\(setting)): \(details)" }
            return "unsupported-setting(\(setting))"
        case let .unsupportedTool(tool, details):
            if let details { return "unsupported-tool(\(tool)): \(details)" }
            return "unsupported-tool(\(tool))"
        case let .other(message):
            return "other(\(message))"
        }
    }
}

private extension TypedToolCall {
    func logDescription() -> String {
        switch self {
        case .static(let call):
            return "\(call.toolName) [\(call.toolCallId)] input=\(call.input)"
        case .dynamic(let call):
            return "\(call.toolName) [\(call.toolCallId)] input=\(call.input)"
        }
    }
}

private extension TypedToolResult {
    func logDescription() -> String {
        switch self {
        case .static(let result):
            return "\(result.toolName) [\(result.toolCallId)] result=\(result.output)"
        case .dynamic(let result):
            return "\(result.toolName) [\(result.toolCallId)] result=\(result.output)"
        }
    }
}

private extension Source {
    func logDescription() -> String {
        switch self {
        case let .url(id, url, title, _):
            return "[\(id)] url=\(url) title=\(title ?? "")"
        default:
            return "unknown"
        }
    }
}

private extension GeneratedFile {
    func logDescription() -> String {
        if let typed = self as? DefaultGeneratedFileWithType {
            let data = typed.data
            return "type=\(typed.mediaType) size=\(data.count)"
        }
        return "file"
    }
}

private extension LanguageModelUsage {
    func logDescription() -> String {
        var parts: [String] = []
        if let inputTokens { parts.append("input=\(inputTokens)") }
        if let outputTokens { parts.append("output=\(outputTokens)") }
        if let totalTokens { parts.append("total=\(totalTokens)") }
        if let reasoningTokens { parts.append("reasoning=\(reasoningTokens)") }
        if let cachedInputTokens { parts.append("cached=\(cachedInputTokens)") }
        return parts.isEmpty ? "" : parts.joined(separator: " ")
    }
}

public extension StreamTextV2LogOptions {
    static func defaultTimestampFormatter(_ date: Date) -> String {
        let value = date.timeIntervalSince1970
        return String(format: "%.3f", value)
    }
}
