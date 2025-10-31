import PackagePlugin

@main
struct GenerateReleaseVersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
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
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension GenerateReleaseVersionPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let baseDirectory: URL
        if let packageDirectory = context.packageDirectory {
            baseDirectory = packageDirectory
        } else {
            baseDirectory = URL(fileURLWithPath: context.xcodeProject.directoryURL.path)
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
    }
}
#endif
