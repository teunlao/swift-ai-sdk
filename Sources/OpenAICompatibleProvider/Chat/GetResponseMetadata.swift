import Foundation

public func openAICompatibleResponseMetadata(
    id: String?,
    model: String?,
    created: Double?
) -> (id: String?, modelId: String?, timestamp: Date?) {
    // Some providers send zero while real response metadata is still pending.
    let timestamp = created.flatMap { $0 == 0 ? nil : Date(timeIntervalSince1970: $0) }
    return (id, model, timestamp)
}
