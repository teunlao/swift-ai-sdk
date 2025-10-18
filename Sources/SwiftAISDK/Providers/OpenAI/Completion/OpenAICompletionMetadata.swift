import Foundation

struct OpenAICompletionResponseMetadata {
    let id: String?
    let modelId: String?
    let timestamp: Date?

    init(id: String?, model: String?, created: Double?) {
        self.id = id
        self.modelId = model
        self.timestamp = created.map { Date(timeIntervalSince1970: $0) }
    }
}
