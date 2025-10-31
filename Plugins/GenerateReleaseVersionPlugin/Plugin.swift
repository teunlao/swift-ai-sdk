import PackagePlugin

@main
struct GenerateReleaseVersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        #if compiler(>=6.2)
        let scriptURL = context.package.directoryURL
            .appendingPathComponent("scripts")
            .appendingPathComponent("update-release-version.sh")
        let outputDirURL = context.pluginWorkDirectoryURL
            .appendingPathComponent("GeneratedVersion")
        let outputFileURL = outputDirURL.appendingPathComponent("SDKReleaseVersion.generated.swift")

        return [
            .prebuildCommand(
                displayName: "Generate release version",
                executable: scriptURL,
                arguments: ["--output", outputFileURL.path],
                outputFilesDirectory: outputDirURL
            )
        ]
        #else
        let scriptPath = context.package.directory.appending(["scripts", "update-release-version.sh"])
        let outputDir = context.pluginWorkDirectory.appending("GeneratedVersion")
        let outputFile = outputDir.appending("SDKReleaseVersion.generated.swift")

        return [
            .prebuildCommand(
                displayName: "Generate release version",
                executable: scriptPath,
                arguments: ["--output", outputFile.string],
                outputFilesDirectory: outputDir
            )
        ]
        #endif
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension GenerateReleaseVersionPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        #if compiler(>=6.2)
        let baseDirectory: URL
        if let packageDirectory = context.packageDirectory {
            baseDirectory = packageDirectory
        } else {
            baseDirectory = URL(fileURLWithPath: context.xcodeProject.directory.string)
        }

        let scriptURL = baseDirectory
            .appendingPathComponent("scripts")
            .appendingPathComponent("update-release-version.sh")
        let outputDirURL = context.pluginWorkDirectoryURL
            .appendingPathComponent("GeneratedVersion")
        let outputFileURL = outputDirURL.appendingPathComponent("SDKReleaseVersion.generated.swift")

        return [
            .prebuildCommand(
                displayName: "Generate release version",
                executable: scriptURL,
                arguments: ["--output", outputFileURL.path],
                outputFilesDirectory: outputDirURL
            )
        ]
        #else
        let packageDir = context.xcodeProject.directory
        let scriptPath = packageDir.appending(["scripts", "update-release-version.sh"])
        let outputDir = context.pluginWorkDirectory.appending("GeneratedVersion")
        let outputFile = outputDir.appending("SDKReleaseVersion.generated.swift")

        return [
            .prebuildCommand(
                displayName: "Generate release version",
                executable: scriptPath,
                arguments: ["--output", outputFile.string],
                outputFilesDirectory: outputDir
            )
        ]
        #endif
    }
}
#endif
