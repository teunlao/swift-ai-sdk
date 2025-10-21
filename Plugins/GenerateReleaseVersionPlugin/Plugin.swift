import PackagePlugin

@main
struct GenerateReleaseVersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
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
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension GenerateReleaseVersionPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let scriptPath = context.packageDirectory.appending(["scripts", "update-release-version.sh"])
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
    }
}
#endif
