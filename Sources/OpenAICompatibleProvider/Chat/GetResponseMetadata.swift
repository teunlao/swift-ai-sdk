import Foundation

public func openAICompatibleResponseMetadata(
    id: String?,
    model: String?,
    created: Double?
) -> (id: String?, modelId: String?, timestamp: Date?) {
    let timestamp = created.map { Date(timeIntervalSince1970: $0) }
    return (id, model, timestamp)
}
