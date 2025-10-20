import Foundation

/// Simple logger for examples with colored output
public struct Logger {
  public enum Level: String {
    case debug = "DEBUG"
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARNING"
    case error = "ERROR"

    var emoji: String {
      switch self {
      case .debug: return "🔍"
      case .info: return "ℹ️"
      case .success: return "✅"
      case .warning: return "⚠️"
      case .error: return "❌"
      }
    }

    var color: String {
      switch self {
      case .debug: return "\u{001B}[0;36m"      // Cyan
      case .info: return "\u{001B}[0;37m"       // White
      case .success: return "\u{001B}[0;32m"    // Green
      case .warning: return "\u{001B}[0;33m"    // Yellow
      case .error: return "\u{001B}[0;31m"      // Red
      }
    }
  }

  private static let reset = "\u{001B}[0m"

  /// Current log level from environment
  public static var currentLevel: Level = {
    let levelStr = ProcessInfo.processInfo.environment["LOG_LEVEL"] ?? "info"
    return Level(rawValue: levelStr.uppercased()) ?? .info
  }()

  /// Log a message at the specified level
  /// - Parameters:
  ///   - level: Log level
  ///   - message: Message to log
  ///   - file: Source file (automatically populated)
  ///   - line: Source line (automatically populated)
  public static func log(
    _ level: Level,
    _ message: String,
    file: String = #file,
    line: Int = #line
  ) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let filename = (file as NSString).lastPathComponent
    let location = "[\(filename):\(line)]"

    let formatted = "\(level.color)\(level.emoji) \(level.rawValue)\(reset) \(timestamp) \(location) \(message)"
    print(formatted)
  }

  /// Log debug message (only if LOG_LEVEL=debug)
  public static func debug(
    _ message: String,
    file: String = #file,
    line: Int = #line
  ) {
    guard currentLevel == .debug else { return }
    log(.debug, message, file: file, line: line)
  }

  /// Log info message
  public static func info(
    _ message: String,
    file: String = #file,
    line: Int = #line
  ) {
    log(.info, message, file: file, line: line)
  }

  /// Log success message
  public static func success(
    _ message: String,
    file: String = #file,
    line: Int = #line
  ) {
    log(.success, message, file: file, line: line)
  }

  /// Log warning message
  public static func warning(
    _ message: String,
    file: String = #file,
    line: Int = #line
  ) {
    log(.warning, message, file: file, line: line)
  }

  /// Log error message
  public static func error(
    _ message: String,
    file: String = #file,
    line: Int = #line
  ) {
    log(.error, message, file: file, line: line)
  }

  /// Log error with Error object
  public static func error(
    _ error: Error,
    file: String = #file,
    line: Int = #line
  ) {
    log(.error, "Error: \(error.localizedDescription)", file: file, line: line)
  }

  /// Print a separator line
  public static func separator(_ char: Character = "─", length: Int = 80) {
    print(String(repeating: char, count: length))
  }

  /// Print a section header
  public static func section(_ title: String) {
    separator()
    print("  \(title.uppercased())")
    separator()
  }
}
