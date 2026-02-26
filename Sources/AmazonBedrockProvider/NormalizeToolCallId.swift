import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/normalize-tool-call-id.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

func isMistralModel(_ modelId: String) -> Bool {
    modelId.contains("mistral.")
}

func normalizeToolCallId(_ toolCallId: String, isMistral: Bool) -> String {
    guard isMistral else { return toolCallId }

    let filtered = toolCallId.unicodeScalars.filter { scalar in
        CharacterSet.alphanumerics.contains(scalar)
    }

    let prefix = filtered.prefix(9)
    return String(String.UnicodeScalarView(prefix))
}

