import Foundation

public struct ExampleEntry {
  public let path: String
  public let description: String
  public let run: () async throws -> Void

  public init(path: String, description: String, run: @escaping () async throws -> Void) {
    self.path = path
    self.description = description
    self.run = run
  }
}

public enum ExampleCatalog {
  private static var lock = NSLock()
  private static var entries: [String: ExampleEntry] = [:]

  @discardableResult
  public static func register(_ entry: ExampleEntry) -> ExampleEntry {
    lock.lock()
    defer { lock.unlock() }
    entries[entry.path] = entry
    return entry
  }

  @discardableResult
  public static func register<T: Example>(_ example: T.Type, path: String? = nil) -> ExampleEntry {
    let key = path ?? T.name
    let entry = ExampleEntry(path: key, description: T.description) {
      await ExampleRunner.execute(T.self)
    }
    return register(entry)
  }

  public static func all() -> [ExampleEntry] {
    lock.lock()
    let values = Array(entries.values)
    lock.unlock()
    return values.sorted { $0.path < $1.path }
  }

  public static func entry(for path: String) -> ExampleEntry? {
    lock.lock()
    let entry = entries[path]
    lock.unlock()
    return entry
  }
}
