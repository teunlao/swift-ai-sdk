import Foundation

struct PlaygroundEnvironment {
    var values: [String: String]

    subscript(_ key: String) -> String? {
        values[key]
    }
}

struct EnvironmentLoaderError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct EnvironmentLoader {
    private let processInfo: ProcessInfo
    private let fileManager: FileManager
    private let envFilePath: String?

    init(
        processInfo: ProcessInfo,
        fileManager: FileManager,
        defaultEnvFile: String?
    ) {
        self.processInfo = processInfo
        self.fileManager = fileManager
        self.envFilePath = defaultEnvFile
    }

    func load() throws -> PlaygroundEnvironment {
        var values = processInfo.environment

        if let envPath = try resolveEnvFilePath() {
            let url = URL(fileURLWithPath: envPath)
            let data = try Data(contentsOf: url)
            guard let contents = String(data: data, encoding: .utf8) else {
                throw EnvironmentLoaderError(message: "Не удалось прочитать .env файл по пути \(envPath)")
            }
            let parsed = parseEnvFile(contents)
            values.merge(parsed) { current, new in
                // Variables from process environment take precedence.
                current
            }
        }

        return PlaygroundEnvironment(values: values)
    }

    private func resolveEnvFilePath() throws -> String? {
        if let custom = envFilePath {
            return custom
        }

        // Default: .env in current working directory (worktree root).
        let cwd = fileManager.currentDirectoryPath
        let defaultPath = (cwd as NSString).appendingPathComponent(".env")
        if fileManager.fileExists(atPath: defaultPath) {
            return defaultPath
        }
        return nil
    }

    private func parseEnvFile(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let separatorIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separatorIndex].trimmingCharacters(in: .whitespaces)
            let valueStart = trimmed.index(after: separatorIndex)
            var value = trimmed[valueStart...].trimmingCharacters(in: .whitespaces)

            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }

            result[String(key)] = String(value)
        }

        return result
    }
}
