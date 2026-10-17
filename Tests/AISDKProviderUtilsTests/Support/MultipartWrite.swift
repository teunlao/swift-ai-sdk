#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

final class MultipartWrite: @unchecked Sendable {
    private typealias Write = @convention(c) (OutputStream, Selector, UnsafePointer<UInt8>, Int) -> Int
    private static let registry = NSLock()
    nonisolated(unsafe) private static weak var active: MultipartWrite?
    nonisolated(unsafe) private static var command: Write?

    let entered = AsyncStream<Void>.makeStream()
    private let lock = NSLock()
    private let marker: Data
    private let method: Method
    private let original: IMP
    private var observed = false
    private var restored = false

    init(marker: String) throws {
        self.marker = Data(marker.utf8)
        var input: InputStream?
        var output: OutputStream?
        Stream.getBoundStreams(withBufferSize: 64 << 10, inputStream: &input, outputStream: &output)
        defer { input?.close(); output?.close() }
        guard let streamClass = output.flatMap(object_getClass),
              let method = class_getInstanceMethod(streamClass, #selector(OutputStream.write(_:maxLength:))),
              let replacement = class_getInstanceMethod(OutputStream.self, #selector(OutputStream.fixtureWrite(_:maxLength:))) else {
            throw FixtureFailure.unavailable
        }
        self.method = method
        original = method_getImplementation(method)
        Self.registry.lock()
        Self.command = unsafeBitCast(original, to: Write.self)
        Self.active = self
        method_setImplementation(method, method_getImplementation(replacement))
        Self.registry.unlock()
    }

    func restore() {
        lock.lock()
        guard !restored else { lock.unlock(); return }
        restored = true
        lock.unlock()
        Self.registry.lock()
        method_setImplementation(method, original)
        Self.active = nil
        Self.registry.unlock()
        entered.continuation.finish()
    }

    deinit { restore() }

    private func capture(_ bytes: UnsafePointer<UInt8>, length: Int) {
        guard length > 64 << 10 else { return }
        let prefix = Data(bytes: bytes, count: min(length, 512))
        lock.lock()
        let matches = !observed && prefix.range(of: marker) != nil
        if matches { observed = true }
        lock.unlock()
        if matches { entered.continuation.yield() }
    }

    fileprivate static func write(_ stream: OutputStream, bytes: UnsafePointer<UInt8>, length: Int) -> Int {
        let (fixture, command) = registry.withLock { (active, Self.command) }
        fixture?.capture(bytes, length: length)
        return command!(stream, #selector(OutputStream.write(_:maxLength:)), bytes, length)
    }

    private enum FixtureFailure: Error { case unavailable }
}

private extension OutputStream {
    @objc func fixtureWrite(_ bytes: UnsafePointer<UInt8>, maxLength: Int) -> Int {
        MultipartWrite.write(self, bytes: bytes, length: maxLength)
    }
}
#endif
