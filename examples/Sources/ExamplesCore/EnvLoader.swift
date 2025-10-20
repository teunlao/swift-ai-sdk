import Foundation

/// Utility for loading environment variables from .env file
public struct EnvLoader {
  /// Errors that can occur during environment loading
  public enum Error: Swift.Error, LocalizedError {
    case envFileNotFound(path: String)
    case invalidFormat(line: String)

    public var errorDescription: String? {
      switch self {
      case .envFileNotFound(let path):
        return "Environment file not found at: \(path)\nCopy .env.example to .env and add your API keys."
      case .invalidFormat(let line):
        return "Invalid format in .env file: \(line)"
      }
    }
  }

  /// Load environment variables from .env file
  /// - Parameter path: Optional custom path to .env file. Defaults to examples/.env
  /// - Throws: Error if file not found or invalid format
  public static func load(from path: String? = nil) throws {
    let envPath = path ?? findEnvFile()

    guard FileManager.default.fileExists(atPath: envPath) else {
      throw Error.envFileNotFound(path: envPath)
    }

    let contents = try String(contentsOfFile: envPath, encoding: .utf8)
    let lines = contents.components(separatedBy: .newlines)

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Skip empty lines and comments
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
        continue
      }

      // Parse KEY=VALUE format
      let parts = trimmed.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else {
        throw Error.invalidFormat(line: trimmed)
      }

      let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
      let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

      // Set environment variable
      setenv(key, value, 1)
    }

    Logger.debug("Loaded environment from: \(envPath)")
  }

  /// Find .env file by searching up the directory tree
  private static func findEnvFile() -> String {
    let fileManager = FileManager.default
    var currentPath = fileManager.currentDirectoryPath

    // Try current directory and parents
    for _ in 0..<5 {
      let envPath = (currentPath as NSString).appendingPathComponent(".env")
      if fileManager.fileExists(atPath: envPath) {
        return envPath
      }

      // Check examples/.env
      let examplesEnvPath = (currentPath as NSString).appendingPathComponent("examples/.env")
      if fileManager.fileExists(atPath: examplesEnvPath) {
        return examplesEnvPath
      }

      // Move up one directory
      currentPath = (currentPath as NSString).deletingLastPathComponent
      if currentPath == "/" {
        break
      }
    }

    // Default to examples/.env
    return "examples/.env"
  }

  /// Get required environment variable
  /// - Parameter key: Environment variable name
  /// - Returns: Value of the environment variable
  /// - Throws: Error if variable is not set
  public static func require(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
      throw NSError(
        domain: "EnvLoader",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Required environment variable '\(key)' is not set.\nAdd it to your .env file."
        ]
      )
    }
    return value
  }

  /// Get optional environment variable
  /// - Parameters:
  ///   - key: Environment variable name
  ///   - default: Default value if not set
  /// - Returns: Value of the environment variable or default
  public static func get(_ key: String, default defaultValue: String = "") -> String {
    return ProcessInfo.processInfo.environment[key] ?? defaultValue
  }
}
