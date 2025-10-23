import Foundation

/// Extracts response metadata from xAI API payloads.
/// Mirrors `packages/xai/src/get-response-metadata.ts`.
public func xaiResponseMetadata(id: String?, model: String?, created: Double?) -> (id: String?, modelId: String?, timestamp: Date?) {
    let timestamp = created.map { Date(timeIntervalSince1970: $0) }
    return (id: id, modelId: model, timestamp: timestamp)
}
