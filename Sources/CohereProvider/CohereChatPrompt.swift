import AISDKProvider

struct CohereChatPromptConversion {
    let messages: [JSONValue]
    let documents: [JSONValue]
    let warnings: [SharedV4Warning]
}

enum CohereToolChoice: String, Sendable {
    case none = "NONE"
    case required = "REQUIRED"
}
