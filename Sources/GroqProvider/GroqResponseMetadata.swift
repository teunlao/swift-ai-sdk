import Foundation

struct GroqResponseMetadata {
    let id: String?
    let modelId: String?
    let timestamp: Date?
}

func groqResponseMetadata(id: String?, model: String?, created: Double?) -> GroqResponseMetadata {
    let timestamp: Date?
    if let created {
        timestamp = Date(timeIntervalSince1970: created)
    } else {
        timestamp = nil
    }
    return GroqResponseMetadata(id: id ?? nil, modelId: model ?? nil, timestamp: timestamp)
}
