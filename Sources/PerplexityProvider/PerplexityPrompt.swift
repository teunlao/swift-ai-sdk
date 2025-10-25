import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/perplexity-language-model-prompt.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct PerplexityPrompt: Encodable, Sendable {
    let messages: [PerplexityMessage]

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(messages)
    }
}

struct PerplexityMessage: Encodable, Sendable {
    enum Role: String, Encodable {
        case system
        case user
        case assistant
    }

    enum Content: Encodable, Sendable {
        case text(String)
        case rich([PerplexityMessageContent])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .rich(let items):
                try container.encode(items)
            }
        }
    }

    let role: Role
    let content: Content

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
    }
}

struct PerplexityMessageContent: Encodable, Sendable {
    enum Kind {
        case text(String)
        case imageURL(String)
    }

    let kind: Kind

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURL(url: url), forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private struct ImageURL: Encodable, Sendable {
        let url: String
    }
}
