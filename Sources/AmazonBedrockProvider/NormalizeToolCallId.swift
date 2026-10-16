import Foundation

func isMistralModel(_ modelId: String) -> Bool {
    modelId.contains("mistral.")
}

func normalizeToolCallId(_ toolCallId: String, isMistral: Bool) -> String {
    guard isMistral else { return toolCallId }
    if toolCallId.range(of: "\\A[a-zA-Z0-9]{9}\\z", options: .regularExpression) != nil {
        return toolCallId
    }

    var hash: UInt64 = 14_695_981_039_346_656_037
    for codeUnit in toolCallId.utf16 {
        hash = (hash ^ UInt64(codeUnit)) &* 1_099_511_628_211
    }
    let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    var value = hash % 13_537_086_546_263_552
    var result = ""
    for _ in 0..<9 {
        result.insert(alphabet[Int(value % 62)], at: result.startIndex)
        value /= 62
    }
    return result
}
