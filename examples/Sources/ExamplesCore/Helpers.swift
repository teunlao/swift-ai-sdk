import Foundation

/// Helper utilities for examples
public struct Helpers {
  /// Print a formatted JSON value
  /// - Parameter value: Any encodable value
  public static func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
      let data = try encoder.encode(value)
      if let string = String(data: data, encoding: .utf8) {
        print(string)
      }
    } catch {
      Logger.error("Failed to encode JSON: \(error)")
    }
  }

  /// Format a duration in human-readable format
  /// - Parameter seconds: Duration in seconds
  /// - Returns: Formatted string (e.g., "1.23s", "123ms")
  public static func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 1 {
      return String(format: "%.0fms", seconds * 1000)
    } else {
      return String(format: "%.2fs", seconds)
    }
  }

  /// Truncate a string to a maximum length
  /// - Parameters:
  ///   - string: String to truncate
  ///   - maxLength: Maximum length
  ///   - suffix: Suffix to append if truncated
  /// - Returns: Truncated string
  public static func truncate(_ string: String, to maxLength: Int, suffix: String = "...") -> String {
    if string.count <= maxLength {
      return string
    }
    let endIndex = string.index(string.startIndex, offsetBy: maxLength - suffix.count)
    return String(string[..<endIndex]) + suffix
  }

  /// Create a temporary file with content
  /// - Parameters:
  ///   - content: Content to write
  ///   - extension: File extension
  /// - Returns: URL to temporary file
  /// - Throws: Error if file creation fails
  public static func createTempFile(content: String, extension ext: String = "txt") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let filename = UUID().uuidString + "." + ext
    let fileURL = tempDir.appendingPathComponent(filename)

    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  /// Create a temporary file with data
  /// - Parameters:
  ///   - data: Data to write
  ///   - extension: File extension
  /// - Returns: URL to temporary file
  /// - Throws: Error if file creation fails
  public static func createTempFile(data: Data, extension ext: String) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let filename = UUID().uuidString + "." + ext
    let fileURL = tempDir.appendingPathComponent(filename)

    try data.write(to: fileURL)
    return fileURL
  }

  /// Remove a file at URL
  /// - Parameter url: URL to file
  public static func removeFile(at url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  /// Measure execution time of a block
  /// - Parameter block: Block to measure
  /// - Returns: Tuple of (result, duration in seconds)
  public static func measure<T>(_ block: () throws -> T) rethrows -> (result: T, duration: TimeInterval) {
    let start = Date()
    let result = try block()
    let duration = Date().timeIntervalSince(start)
    return (result, duration)
  }

  /// Measure execution time of an async block
  /// - Parameter block: Async block to measure
  /// - Returns: Tuple of (result, duration in seconds)
  public static func measure<T>(_ block: () async throws -> T) async rethrows -> (result: T, duration: TimeInterval) {
    let start = Date()
    let result = try await block()
    let duration = Date().timeIntervalSince(start)
    return (result, duration)
  }
}
