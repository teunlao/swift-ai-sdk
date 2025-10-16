import ArgumentParser

struct PlaygroundCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "playground",
        abstract: "Swift AI SDK playground CLI.",
        version: PlaygroundVersion.current.description,
        subcommands: [
            ChatCommand.self
        ],
        defaultSubcommand: ChatCommand.self
    )

    mutating func run() async throws {
        // If user runs without subcommand, fall back to help (defaultSubcommand will trigger ChatCommand).
    }
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Enable verbose logging output.")
    var verbose: Bool = false

    @Option(name: .long, help: "Path to .env file with provider credentials (defaults to project root).")
    var envFile: String?

    @MainActor
    func bootstrapContext() async throws {
        if PlaygroundContext.shared != nil { return }

        let logger = PlaygroundLogger.shared
        await logger.setVerbose(verbose)

        let loader = EnvironmentLoader(
            processInfo: .processInfo,
            fileManager: .default,
            defaultEnvFile: envFile
        )

        let environment = try loader.load()
        let configuration = PlaygroundConfiguration(environment: environment)

        PlaygroundContext.shared = PlaygroundContext(configuration: configuration, logger: logger)
    }
}
