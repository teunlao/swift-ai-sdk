import Foundation
import Testing
@testable import AISDKProvider

@Suite("LanguageModelV4 wire shapes")
struct LanguageModelV4WireShapeTests {
    private func json(_ value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    @Test("text-end carries citations and tool-input-start carries the input encoding")
    func streamPartsCarryCitationsAndInputEncoding() throws {
        let citation = LanguageModelV4Citation(
            source: .url(id: "s1", url: "https://example.com", title: "Example", providerMetadata: nil),
            startIndex: 0,
            endIndex: 5,
            citedText: "Hello"
        )
        let parts: [LanguageModelV4StreamPart] = [
            .textEnd(id: "t1", providerMetadata: nil, citations: [citation]),
            .toolInputStart(
                id: "c1",
                toolName: "shell",
                providerMetadata: nil,
                providerExecuted: nil,
                dynamic: nil,
                title: nil,
                inputEncoding: .text
            ),
        ]

        let encoded = try json(parts)
        #expect(encoded == [
            [
                "type": "text-end",
                "id": "t1",
                "citations": [[
                    "source": ["type": "source", "sourceType": "url", "id": "s1", "url": "https://example.com", "title": "Example"],
                    "startIndex": 0,
                    "endIndex": 5,
                    "citedText": "Hello",
                ]],
            ],
            ["type": "tool-input-start", "id": "c1", "toolName": "shell", "inputEncoding": "text"],
        ])

        let decoded = try JSONDecoder().decode([LanguageModelV4StreamPart].self, from: JSONEncoder().encode(parts))
        #expect(decoded == parts)
    }

    @Test("url file data keeps the original URL string")
    func urlFileDataKeepsOriginalURL() throws {
        let data = SharedV4FileData.url(URL(string: "gs://bucket/a%20b")!, originalUrl: "gs://bucket/a b")

        #expect(try json(data) == ["type": "url", "url": "gs://bucket/a%20b", "originalUrl": "gs://bucket/a b"])
        #expect(try JSONDecoder().decode(SharedV4FileData.self, from: JSONEncoder().encode(data)) == data)
    }
}
