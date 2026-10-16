import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Fingerprints the server-controlled, security-relevant fields of each tool:
 the fixed description, the resolved input JSON schema and the title.

 Port of `fingerprintTools` from `@ai-sdk/ai/src/generate-text/tool-fingerprint.ts`.
 Capture a baseline at trust time and compare later fetches with
 `detectToolDrift` to catch tool-definition drift. A description resolved per
 call is developer-owned, so only its presence is pinned.
 */
public func fingerprintTools(_ tools: ToolSet) async throws -> [String: String] {
    var fingerprints: [String: String] = [:]
    for (name, tool) in tools {
        var definition: [String: JSONValue] = [
            "description": taggedDescription(tool.description),
            "inputSchema": try await tool.inputSchema.resolve().jsonSchema(),
        ]
        if let title = tool.title {
            definition["title"] = .string(title)
        }
        fingerprints[name] = try hashCanonical(.object(definition))
    }
    return fingerprints
}

/// Tools added, removed or changed between two fingerprint maps.
public struct ToolDrift: Sendable, Equatable {
    public let added: [String]
    public let removed: [String]
    public let changed: [String]

    public init(added: [String], removed: [String], changed: [String]) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }
}

/**
 Diffs two fingerprint maps produced by `fingerprintTools`. Names are sorted.

 Port of `detectToolDrift` from `@ai-sdk/ai/src/generate-text/tool-fingerprint.ts`.
 */
public func detectToolDrift(current: [String: String], baseline: [String: String]) -> ToolDrift {
    ToolDrift(
        added: current.keys.filter { baseline[$0] == nil }.sorted(),
        removed: baseline.keys.filter { current[$0] == nil }.sorted(),
        changed: current.filter { name, digest in baseline[name].map { $0 != digest } ?? false }.keys.sorted()
    )
}

// The tagged shape keeps a literal string from ever hashing like a resolved description.
private func taggedDescription(_ description: ToolDescription?) -> JSONValue {
    switch description {
    case .text(let text)?:
        return .object(["type": .string("string"), "value": .string(text)])
    case .resolve?:
        return .object(["type": .string("function")])
    case nil:
        return .object(["type": .string("none")])
    }
}
