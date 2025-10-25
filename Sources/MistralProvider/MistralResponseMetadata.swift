import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/get-response-metadata.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct MistralResponseMetadata: Sendable {
    let id: String?
    let modelId: String?
    let timestamp: Date?
}

func mistralResponseMetadata(id: String?, model: String?, created: Double?) -> MistralResponseMetadata {
    let timestamp: Date?
    if let created {
        timestamp = Date(timeIntervalSince1970: created)
    } else {
        timestamp = nil
    }

    return MistralResponseMetadata(
        id: id,
        modelId: model,
        timestamp: timestamp
    )
}
