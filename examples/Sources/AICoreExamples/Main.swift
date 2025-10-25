import ExamplesCore
import Foundation

@main
struct AICoreExamplesCLI {
  static func main() async {
    registerAllExamples()

    let args = Array(CommandLine.arguments.dropFirst())

    if args.contains("--help") || args.contains("-h") {
      printHelp()
      return
    }

    if args.contains("--list") {
      listExamples()
      return
    }

    guard let path = args.first else {
      printHelp()
      exit(1)
    }

    guard let entry = ExampleCatalog.entry(for: path) else {
      Logger.error("Unknown example: \(path)\nUse --list to see available examples.")
      exit(1)
    }

    do {
      try EnvLoader.load()
      let start = Date()
      try await entry.run()
      let duration = Date().timeIntervalSince(start)
      Logger.separator()
      Logger.success("Example \(path) completed in \(String(format: "%.2f", duration))s")
    } catch {
      Logger.separator()
      Logger.error(error)
      exit(1)
    }
  }

  private static func listExamples() {
    Logger.section("Available Examples")
    for entry in ExampleCatalog.all() {
      Logger.info("• \(entry.path) — \(entry.description)")
    }
  }

  private static func printHelp() {
    let command = CommandLine.arguments.first ?? "swift run AICoreExamples"
    print("""
    Usage: \(command) <example-path>
           \(command) --list

    Options:
      --list          List all available examples
      -h, --help      Show this help information
    """)
  }
}
