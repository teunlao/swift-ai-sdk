import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/alibaba-chat-prompt.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct AlibabaCacheControl: Sendable, Equatable, Codable {
    public let type: String

    public init(type: String) {
        self.type = type
    }
}

