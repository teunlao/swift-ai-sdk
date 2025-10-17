import Foundation

/// Utility to observe and introspect a StreamText V2 full stream.
///
/// This helper is designed for diagnostics and test scaffolding: it attaches to an
/// `AsyncSequence` of `TextStreamPart`, records a replayable log, and provides
/// basic counters and assertions to reason about ordering and presence of events.
///
/// It is intentionally independent from test frameworks and can be used by SDK
/// consumers who need lightweight stream inspection.
public final class StreamTextV2EventRecorder: @unchecked Sendable {
    public private(set) var parts: [TextStreamPart] = []
    public private(set) var finished: Bool = false
    public private(set) var error: Error? = nil

    private var lock = NSLock()
    private var task: Task<Void, Never>? = nil

    public init() {}

    /// Start recording from a full stream.
    /// - Parameter stream: `AsyncThrowingStream<TextStreamPart, Error>` to capture.
    public func attach(to stream: AsyncThrowingStream<TextStreamPart, Error>) {
        task?.cancel()
        finished = false
        error = nil
        parts.removeAll(keepingCapacity: true)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await part in stream {
                    self.append(part)
                }
                self.setFinished()
            } catch {
                self.setError(error)
            }
        }
    }

    /// Cancel recording; the underlying source stream is not cancelled by this method.
    public func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { cancel() }

    // MARK: - Snapshots

    public func snapshot() -> [TextStreamPart] {
        lock.lock(); defer { lock.unlock() }
        return parts
    }

    public func count(where predicate: (TextStreamPart) -> Bool) -> Int {
        lock.lock(); defer { lock.unlock() }
        return parts.reduce(0) { $0 + (predicate($1) ? 1 : 0) }
    }

    public struct Counters: Sendable {
        public let starts: Int
        public let startSteps: Int
        public let finishSteps: Int
        public let finishes: Int
        public let aborts: Int
        public let textStarts: Int
        public let textEnds: Int
        public let textDeltas: Int
        public let reasoningDeltas: Int
        public let toolInputs: Int
        public let toolResults: Int
    }

    /// Aggregates common counters for quick diagnostics.
    public func counters() -> Counters {
        lock.lock(); defer { lock.unlock() }
        var starts = 0, startSteps = 0, finishSteps = 0, finishes = 0, aborts = 0
        var textStarts = 0, textEnds = 0, textDeltas = 0, reasoningDeltas = 0
        var toolInputs = 0, toolResults = 0
        for p in parts {
            switch p {
            case .start: starts += 1
            case .startStep: startSteps += 1
            case .finishStep: finishSteps += 1
            case .finish: finishes += 1
            case .abort: aborts += 1
            case .textStart: textStarts += 1
            case .textDelta: textDeltas += 1
            case .textEnd: textEnds += 1
            case .reasoningDelta: reasoningDeltas += 1
            case .toolInputStart, .toolInputDelta, .toolInputEnd: toolInputs += 1
            case .toolResult: toolResults += 1
            default: break
            }
        }
        return Counters(
            starts: starts,
            startSteps: startSteps,
            finishSteps: finishSteps,
            finishes: finishes,
            aborts: aborts,
            textStarts: textStarts,
            textEnds: textEnds,
            textDeltas: textDeltas,
            reasoningDeltas: reasoningDeltas,
            toolInputs: toolInputs,
            toolResults: toolResults
        )
    }

    public func firstIndex(where predicate: (TextStreamPart) -> Bool) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return parts.firstIndex(where: predicate)
    }

    public func lastIndex(where predicate: (TextStreamPart) -> Bool) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return parts.lastIndex(where: predicate)
    }

    // MARK: - Common predicates

    public static func isStart(_ p: TextStreamPart) -> Bool {
        if case .start = p { return true } else { return false }
    }
    public static func isStartStep(_ p: TextStreamPart) -> Bool {
        if case .startStep = p { return true } else { return false }
    }
    public static func isFinishStep(_ p: TextStreamPart) -> Bool {
        if case .finishStep = p { return true } else { return false }
    }
    public static func isFinish(_ p: TextStreamPart) -> Bool {
        if case .finish = p { return true } else { return false }
    }
    public static func isAbort(_ p: TextStreamPart) -> Bool {
        if case .abort = p { return true } else { return false }
    }
    public static func isTextStart(_ p: TextStreamPart) -> Bool {
        if case .textStart = p { return true } else { return false }
    }
    public static func isTextEnd(_ p: TextStreamPart) -> Bool {
        if case .textEnd = p { return true } else { return false }
    }
    public static func textDelta(_ p: TextStreamPart) -> String? {
        if case let .textDelta(_, t, _) = p { return t } else { return nil }
    }
    public static func reasoningDelta(_ p: TextStreamPart) -> String? {
        if case let .reasoningDelta(_, t, _) = p { return t } else { return nil }
    }

    /// Blocks until recording is finished or the timeout elapses.
    /// - Returns: true if finished, false if timed out.
    public func waitUntilFinished(timeout: TimeInterval = 1.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if finished || error != nil { return true }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        return finished || error != nil
    }

    /// Verifies basic ordering invariant: start → startStep → … → finishStep → finish (or abort).
    /// Returns nil if ordering is valid, or an error string describing the violation.
    public func checkBasicOrdering() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let iStart = parts.firstIndex(where: { StreamTextV2EventRecorder.isStart($0) }) else {
            return "missing .start"
        }
        guard let iStartStep = parts.firstIndex(where: { StreamTextV2EventRecorder.isStartStep($0) }) else {
            return "missing .startStep"
        }
        if iStartStep < iStart { return ".startStep precedes .start" }
        let iFinishStep = parts.lastIndex(where: { StreamTextV2EventRecorder.isFinishStep($0) })
        let iFinish = parts.lastIndex(where: { StreamTextV2EventRecorder.isFinish($0) || StreamTextV2EventRecorder.isAbort($0) })
        if let iFinishStep, let iFinish {
            if iFinishStep > iFinish { return ".finishStep after terminal event" }
        }
        return nil
    }

    // MARK: - Internals

    private func append(_ part: TextStreamPart) {
        lock.lock(); defer { lock.unlock() }
        parts.append(part)
    }
    private func setFinished() {
        lock.lock(); defer { lock.unlock() }
        finished = true
    }
    private func setError(_ err: Error) {
        lock.lock(); defer { lock.unlock() }
        error = err
    }
}
