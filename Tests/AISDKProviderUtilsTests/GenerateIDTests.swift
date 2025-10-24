import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for ID generation utilities.

 Port of `@ai-sdk/provider-utils/src/generate-id.test.ts`
 */
struct GenerateIDTests {
    @Test("createIDGenerator generates ID with correct custom length")
    func testCustomLength() throws {
        let idGenerator = try createIDGenerator(size: 10)
        let id = idGenerator()

        #expect(id.count == 10)
    }

    @Test("createIDGenerator generates ID with correct default length")
    func testDefaultLength() throws {
        let idGenerator = try createIDGenerator()
        let id = idGenerator()

        #expect(id.count == 16)
    }

    @Test("createIDGenerator throws error if separator is part of alphabet")
    func testSeparatorInAlphabet() throws {
        #expect(throws: InvalidArgumentError.self) {
            _ = try createIDGenerator(prefix: "b", separator: "a")
        }
    }

    @Test("createIDGenerator with prefix includes prefix and separator")
    func testPrefixFormat() throws {
        let idGenerator = try createIDGenerator(prefix: "test", separator: "-", size: 8)
        let id = idGenerator()

        // Should be "test-XXXXXXXX" (8 random chars)
        #expect(id.hasPrefix("test-"))
        #expect(id.count == 13) // "test" (4) + "-" (1) + random (8)
    }

    @Test("generateID generates unique IDs")
    func testUniqueIDs() throws {
        let id1 = generateID()
        let id2 = generateID()

        #expect(id1 != id2)
    }

    @Test("generateID has correct default length")
    func testGenerateIDDefaultLength() throws {
        let id = generateID()
        #expect(id.count == 16)
    }

    @Test("createIDGenerator uses only alphabet characters")
    func testAlphabetConstraint() throws {
        let customAlphabet = "ABC"
        let idGenerator = try createIDGenerator(size: 100, alphabet: customAlphabet)
        let id = idGenerator()

        // All characters should be from the custom alphabet
        for char in id {
            #expect(customAlphabet.contains(char))
        }
    }

    @Test("createIDGenerator with empty prefix omits separator")
    func testNoPrefix() throws {
        let idGenerator = try createIDGenerator(size: 10)
        let id = idGenerator()

        // Should not contain separator when no prefix
        #expect(!id.contains("-"))
        #expect(id.count == 10)
    }
}
