import Foundation

/// Base protocol for runnable examples
public protocol Example {
  /// Name of the example
  static var name: String { get }

  /// Description of what this example demonstrates
  static var description: String { get }

  /// Run the example
  static func run() async throws
}

/// Runner for executing examples with consistent setup and teardown
public struct ExampleRunner {
  /// Execute an example with proper setup and error handling
  /// - Parameter example: Example type to run
  public static func execute<T: Example>(_ example: T.Type) async {
    Logger.section(example.name)
    Logger.info(example.description)
    Logger.separator()

    do {
      // Load environment
      try EnvLoader.load()

      // Run example
      let start = Date()
      try await example.run()
      let duration = Date().timeIntervalSince(start)

      // Success
      Logger.separator()
      Logger.success("Example completed successfully in \(String(format: "%.2f", duration))s")
    } catch {
      // Error
      Logger.separator()
      Logger.error(error)
      exit(1)
    }
  }

  /// Run multiple examples in sequence
  /// - Parameter examples: Array of example types to run
  public static func executeAll(_ examples: [any Example.Type]) async {
    Logger.section("Running \(examples.count) Examples")

    var passed = 0
    var failed = 0

    for example in examples {
      do {
        Logger.info("Running: \(example.name)")
        try EnvLoader.load()
        try await example.run()
        Logger.success("✓ \(example.name)")
        passed += 1
      } catch {
        Logger.error("✗ \(example.name): \(error.localizedDescription)")
        failed += 1
      }
      Logger.separator()
    }

    // Summary
    Logger.section("Results")
    Logger.success("Passed: \(passed)")
    if failed > 0 {
      Logger.error("Failed: \(failed)")
      exit(1)
    }
  }
}

/// Example that can be run from command line
public protocol CLIExample: Example {
  /// Main entry point
  static func main() async
}

extension CLIExample {
  public static func main() async {
    await ExampleRunner.execute(Self.self)
  }
}
