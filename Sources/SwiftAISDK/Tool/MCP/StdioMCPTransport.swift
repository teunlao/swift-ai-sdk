#if os(macOS) || os(Linux)
import Foundation
import Dispatch
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct StdioConfig: Sendable {
    public enum StandardError: Sendable {
        case inherit
        case ignore
        case file(FileHandle)
    }

    public let command: String
    public let args: [String]
    public let env: [String: String]?
    public let stderr: StandardError
    public let cwd: String?

    public init(command: String, args: [String] = [], env: [String: String]? = nil, stderr: StandardError = .inherit, cwd: String? = nil) {
        self.command = command
        self.args = args
        self.env = env
        self.stderr = stderr
        self.cwd = cwd
    }
}

public func getEnvironment(_ customEnv: [String: String]? = nil) -> [String: String] {
    var environment = customEnv ?? [:]
    for key in ["HOME", "LOGNAME", "PATH", "SHELL", "TERM", "USER"] where environment[key] == nil {
        if let value = ProcessInfo.processInfo.environment[key], !value.hasPrefix("()") {
            environment[key] = value
        }
    }
    return environment
}

public typealias Experimental_StdioMCPTransport = StdioMCPTransport

public final class StdioMCPTransport: MCPTransport, @unchecked Sendable {
    private let config: StdioConfig
    private let lock = NSLock()
    // Pipe backpressure must not block Swift's cooperative executor.
    private let writer = DispatchQueue(label: "mcp.stdio.write")
    private let readLock = NSLock()
    private var process: Process?
    private var closed = false
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()

    public var onclose: (@Sendable () -> Void)?
    public var onerror: (@Sendable (Error) -> Void)?
    public var onmessage: (@Sendable (JSONRPCMessage) -> Void)?

    public init(_ config: StdioConfig) { self.config = config }

    public func start() async throws {
        let process = Process()
        let inputPipe = Pipe()
        #if canImport(Darwin)
        // A closed child stdin must fail the write instead of signalling the host.
        guard fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        #endif
        let outputPipe = Pipe()
        let environment = getEnvironment(config.env)
        let directory = URL(fileURLWithPath: config.cwd ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let command: String
        if config.command.contains("/") {
            command = URL(fileURLWithPath: config.command, relativeTo: directory).standardizedFileURL.path
        } else {
            command = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":", omittingEmptySubsequences: false)
                .map { URL(fileURLWithPath: $0.isEmpty ? config.command : String($0) + "/" + config.command, relativeTo: directory).standardizedFileURL.path }
                .first { FileManager.default.isExecutableFile(atPath: $0) } ?? config.command
        }
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = config.args
        process.environment = environment
        if let cwd = config.cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        switch config.stderr {
        case .inherit: process.standardError = FileHandle.standardError
        case .ignore: process.standardError = FileHandle.nullDevice
        case .file(let handle): process.standardError = handle
        }
        process.terminationHandler = { [weak self, output = outputPipe.fileHandleForReading] _ in
            guard let self else { return }
            // Deliver the child's final stdout before publishing its closure.
            readLock.withLock {
                output.readabilityHandler = nil
                let remaining = output.readDataToEndOfFile()
                if !remaining.isEmpty { receive(remaining) }
            }
            lock.withLock { self.process = nil; input = nil }
            onclose?()
        }
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            readLock.withLock {
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                receive(data)
            }
        }
        do {
            try lock.withLock {
                try Task.checkCancellation()
                guard !closed else { throw CancellationError() }
                guard self.process == nil else { throw MCPClientError(message: "StdioMCPTransport already started.") }
                self.process = process
                input = inputPipe.fileHandleForWriting
                output = outputPipe.fileHandleForReading
                do { try process.run() }
                catch { self.process = nil; input = nil; output = nil; throw error }
            }
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            onerror?(error)
            throw error
        }
    }

    private func receive(_ data: Data) {
        let lines = lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            while let index = buffer.firstIndex(of: 10) {
                lines.append(Data(buffer[..<index]))
                buffer.removeSubrange(...index)
            }
            return lines
        }
        for line in lines {
            do {
                let message = try JSONDecoder().decode(JSONRPCMessage.self, from: line)
                onmessage?(message)
            }
            catch { onerror?(error) }
        }
    }

    public func send(message: JSONRPCMessage) async throws {
        try Task.checkCancellation()
        guard let input = lock.withLock({ input }) else {
            throw MCPClientError(message: "StdioClientTransport not connected")
        }
        var data = try JSONEncoder().encode(message)
        data.append(10)
        let messageData = data
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.async { [self] in
                do {
                    try write(messageData, to: input)
                    continuation.resume()
                } catch {
                    onerror?(error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func write(_ data: Data, to input: FileHandle) throws {
        #if os(Linux)
        // Restore the caller's signal mask without delivering this write's SIGPIPE.
        var blocked = sigset_t()
        sigemptyset(&blocked)
        sigaddset(&blocked, SIGPIPE)
        var previous = sigset_t()
        let status = pthread_sigmask(SIG_BLOCK, &blocked, &previous)
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO) }
        var pending = sigset_t()
        let hadPending = sigpending(&pending) == 0 && sigismember(&pending, SIGPIPE) == 1
        let wasBlocked = sigismember(&previous, SIGPIPE) == 1
        var brokenPipe = false
        defer {
            if brokenPipe, !wasBlocked, !hadPending {
                var zero = timespec(tv_sec: 0, tv_nsec: 0)
                _ = sigtimedwait(&blocked, nil, &zero)
            }
            _ = pthread_sigmask(SIG_SETMASK, &previous, nil)
        }
        #endif
        do {
            try input.write(contentsOf: data)
        } catch {
            let failure = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError ?? (error as NSError)
            #if os(Linux)
            brokenPipe = failure.domain == NSPOSIXErrorDomain && failure.code == Int(POSIXErrorCode.EPIPE.rawValue)
            #endif
            throw failure
        }
    }

    public func close() async throws {
        let state = lock.withLock {
            closed = true
            let state = (process, input, output)
            process = nil; input = nil; output = nil
            buffer.removeAll()
            return state
        }
        state.2?.readabilityHandler = nil
        try? state.1?.close()
        if state.0?.isRunning == true { state.0?.terminate() }
    }
}
#endif
