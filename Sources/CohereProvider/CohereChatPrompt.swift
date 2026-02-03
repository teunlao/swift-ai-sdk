import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-chat-prompt.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct CohereChatPromptConversion {
    let messages: [JSONValue]
    let documents: [JSONValue]
    let warnings: [SharedV3Warning]
}

enum CohereToolChoice: String, Sendable {
    case none = "NONE"
    case required = "REQUIRED"
}
