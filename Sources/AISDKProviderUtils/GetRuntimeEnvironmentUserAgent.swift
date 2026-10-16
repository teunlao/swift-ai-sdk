import Foundation

/**
 Snapshot of runtime signals used to determine the environment user agent.
 Mirrors the optional parameter from the TypeScript implementation.
 */
public struct RuntimeEnvironmentSnapshot: Sendable {
    public var hasWindow: Bool
    public var navigatorUserAgent: String?
    public var edgeRuntime: Bool
    public var processVersionsNode: String?
    public var processVersion: String?

    public init(
        hasWindow: Bool = false,
        navigatorUserAgent: String? = nil,
        edgeRuntime: Bool = false,
        processVersionsNode: String? = nil,
        processVersion: String? = nil
    ) {
        self.hasWindow = hasWindow
        self.navigatorUserAgent = navigatorUserAgent
        self.edgeRuntime = edgeRuntime
        self.processVersionsNode = processVersionsNode
        self.processVersion = processVersion
    }

    /// Attempts to infer runtime hints from the current Swift process.
    /// Falls back to unknown when no hints are available.
    public static var current: RuntimeEnvironmentSnapshot {
        let env = ProcessInfo.processInfo.environment
        var snapshot = RuntimeEnvironmentSnapshot()

        if let nodeVersion = env["NODE_VERSION"] {
            snapshot.processVersionsNode = nodeVersion
            snapshot.processVersion = nodeVersion
        }

        if env["EDGE_RUNTIME"] != nil {
            snapshot.edgeRuntime = true
        }

        return snapshot
    }
}

/// Returns `true` when the runtime snapshot represents a browser environment.
public func isBrowserRuntime(
    _ snapshot: RuntimeEnvironmentSnapshot = .current
) -> Bool {
    snapshot.hasWindow
}

/**
 Returns the runtime environment user agent string.
 Port of `@ai-sdk/provider-utils/src/get-runtime-environment-user-agent.ts`.
 */
public func getRuntimeEnvironmentUserAgent(
    _ snapshot: RuntimeEnvironmentSnapshot = .current
) -> String {
    // Browsers / Cloudflare Workers / Deno / Bun / Node.js >= 21.1
    if let navigator = snapshot.navigatorUserAgent, !navigator.isEmpty {
        return navigator.lowercased()
    }

    if snapshot.processVersionsNode != nil, let nodeVersion = snapshot.processVersion {
        return "node.js/\(nodeVersion)"
    }

    if snapshot.edgeRuntime {
        return "vercel-edge"
    }

    // Unknown runtimes are omitted from the user agent.
    return ""
}
