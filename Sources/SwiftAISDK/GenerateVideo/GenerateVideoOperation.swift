import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GenerateVideoPollOptions: Sendable {
    public typealias Delay = @Sendable (Double, (@Sendable () -> Bool)?) async throws -> Void
    public let intervalMs: Double
    public let timeoutMs: Double
    public let delay: Delay?

    public init(intervalMs: Double = 5000, timeoutMs: Double = 600_000, delay: Delay? = nil) {
        self.intervalMs = intervalMs
        self.timeoutMs = timeoutMs
        self.delay = delay
    }
}

public typealias GenerateVideoWebhookFactory = @Sendable () async throws -> VideoModelV4Webhook

func validateVideoPollOptions(_ options: GenerateVideoPollOptions?) throws {
    guard let options else { return }
    for (parameter, value) in [("poll.intervalMs", options.intervalMs), ("poll.timeoutMs", options.timeoutMs)] {
        guard value.isFinite else {
            throw InvalidArgumentError(parameter: parameter, value: .number(value), message: "\(parameter) must be a finite number")
        }
    }
}

struct VideoGenerationFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func executeVideoOperation(
    model: any VideoModelV4Operations,
    options: VideoModelV4CallOptions,
    statusHeaders: [String: String],
    poll: GenerateVideoPollOptions?,
    webhook: GenerateVideoWebhookFactory?,
    retries: PreparedRetries
) async throws -> VideoModelV4GenerateResult {
    var warnings: [SharedV4Warning] = []
    var registration: VideoModelV4WebhookRegistration?
    if let webhook {
        if let handler = model as? any VideoModelV4WebhookHandler {
            registration = try await handler.handleWebhookOption(webhook: webhook)
        } else {
            warnings.append(.unsupported(feature: "webhook", details: "This model does not support webhooks. Falling back to polling."))
        }
    }
    let webhookUrl = registration?.webhookUrl
    let start = try await retries.retry.call { try await model.doStart(options: options, webhookUrl: webhookUrl) }
    warnings.append(contentsOf: start.warnings)
    var metadata = start.providerMetadata ?? [:]
    let config = poll ?? GenerateVideoPollOptions()
    let pollingDelay = config.delay ?? videoDelay
    let startTime = Date()
    let timeout = VideoGenerationFailure(message: "Video generation timed out after \(videoMilliseconds(config.timeoutMs))ms.")
    if let registration {
        _ = try await withVideoTimeout(
            milliseconds: config.timeoutMs, abortSignal: options.abortSignal,
            timeout: timeout, timeoutDelay: pollingDelay
        ) { _ in try await registration.received.value }
    }
    while true {
        if registration == nil {
            let remaining = config.timeoutMs - Date().timeIntervalSince(startTime) * 1000
            if remaining <= 0 { throw timeout }
            try await pollingDelay(min(config.intervalMs, remaining), options.abortSignal)
            if Date().timeIntervalSince(startTime) * 1000 >= config.timeoutMs { throw timeout }
        }
        let status: VideoModelV4OperationStatusResult
        if registration != nil {
            status = try await retries.retry.call {
                try await model.doStatus(options: .init(
                    operation: start.operation, abortSignal: options.abortSignal, headers: statusHeaders
                ))
            }
        } else {
            let remaining = config.timeoutMs - Date().timeIntervalSince(startTime) * 1000
            status = try await withVideoTimeout(
                milliseconds: remaining, abortSignal: options.abortSignal, timeout: timeout
            ) { signal in
                let statusRetries = try prepareRetries(maxRetries: retries.maxRetries, abortSignal: signal)
                return try await statusRetries.retry.call {
                    try await model.doStatus(options: .init(
                        operation: start.operation, abortSignal: signal, headers: statusHeaders
                    ))
                }
            }
        }
        switch status {
        case .error(let error, _, _):
            throw VideoGenerationFailure(message: error)
        case let .pending(statusWarnings, providerMetadata, _):
            warnings.append(contentsOf: statusWarnings ?? [])
            if let providerMetadata { mergeVideoProviderMetadata(target: &metadata, source: providerMetadata) }
        case let .completed(videos, statusWarnings, providerMetadata, response):
            warnings.append(contentsOf: statusWarnings)
            if let providerMetadata { mergeVideoProviderMetadata(target: &metadata, source: providerMetadata) }
            return VideoModelV4GenerateResult(
                videos: videos, warnings: warnings,
                providerMetadata: metadata.isEmpty ? nil : metadata, response: response
            )
        }
        if registration != nil {
            throw VideoGenerationFailure(message: "Video generation did not complete after webhook notification.")
        }
    }
}

private func videoMilliseconds(_ value: Double) -> String {
    value.isFinite && value.rounded() == value ? String(format: "%.0f", value) : String(value)
}

private func videoDelay(_ milliseconds: Double, _ abortSignal: (@Sendable () -> Bool)?) async throws {
    let bounded = min(max(milliseconds, 0), Double(Int.max / 1_000_000))
    try await delay(Int(bounded), abortSignal: abortSignal)
}

private func withVideoTimeout<Value: Sendable>(
    milliseconds: Double,
    abortSignal: (@Sendable () -> Bool)?,
    timeout: VideoGenerationFailure,
    timeoutDelay: @escaping GenerateVideoPollOptions.Delay = videoDelay,
    operation: @escaping @Sendable (@escaping @Sendable () -> Bool) async throws -> Value
) async throws -> Value {
    let race = VideoOperationRace<Value>()
    let deadline = TimeoutAbortSignalController()
    let signal: @Sendable () -> Bool = { deadline.isAborted() || abortSignal?() == true }
    let timerSignal: @Sendable () -> Bool = { race.isFinished || abortSignal?() == true }
    let request = Task {
        do { race.finish(.success(try await operation(signal))) }
        catch { race.finish(.failure(error)) }
    }
    let timer = Task {
        do {
            try await timeoutDelay(milliseconds, timerSignal)
            deadline.markTotalTimedOut()
            race.finish(.failure(timeout))
        } catch { race.finish(.failure(error)) }
    }
    defer {
        request.cancel()
        timer.cancel()
    }
    return try await withTaskCancellationHandler {
        try await race.value()
    } onCancel: {
        deadline.markTotalTimedOut()
        race.finish(.failure(CancellationError()))
    }
}

// Unstructured competitors let a deadline finish even when a provider ignores cancellation.
private final class VideoOperationRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}
