import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("Provider reference utilities")
struct ProviderReferenceTests {
    @Test("isProviderReference accepts provider id maps")
    func isProviderReferenceAcceptsProviderMaps() {
        #expect(isProviderReference(["openai": "file-abc123"] as SharedV4ProviderReference))
        #expect(isProviderReference(["fileId": "abc"] as SharedV4ProviderReference))
        #expect(isProviderReference(JSONValue.object(["anthropic": .string("file-xyz")])) == true)
    }

    @Test("isProviderReference rejects tagged data and non-reference values")
    func isProviderReferenceRejectsTaggedAndNonReferenceValues() {
        #expect(!isProviderReference(["type": "reference", "reference": ["fileId": "abc"]] as [String: Any]))
        #expect(!isProviderReference(["type": "data", "data": "x"] as [String: Any]))
        #expect(!isProviderReference(Data([1, 2, 3])))
        #expect(!isProviderReference(URL(string: "https://example.com/file")!))
        #expect(!isProviderReference(NSNull()))
        #expect(!isProviderReference("some-string"))
        #expect(!isProviderReference(42))
        #expect(!isProviderReference(["openai": 123] as [String: Any]))
        #expect(!isProviderReference(JSONValue.object(["openai": .number(123)])))
    }

    @Test("resolveProviderReference returns provider-specific identifiers")
    func resolveProviderReferenceReturnsIdentifiers() throws {
        let reference: SharedV4ProviderReference = [
            "openai": "file-abc",
            "anthropic": "file-xyz"
        ]

        #expect(try resolveProviderReference(reference: reference, provider: "openai") == "file-abc")
        #expect(try resolveProviderReference(reference: reference, provider: "anthropic") == "file-xyz")
        #expect(try resolveProviderReference(reference: ["openai": "file-only"], provider: "openai") == "file-only")
    }

    @Test("resolveProviderReference throws NoSuchProviderReferenceError")
    func resolveProviderReferenceThrowsForMissingProvider() throws {
        let reference: SharedV4ProviderReference = [
            "anthropic": "file-xyz",
            "google": "file-123"
        ]

        do {
            _ = try resolveProviderReference(reference: reference, provider: "openai")
            Issue.record("Expected NoSuchProviderReferenceError")
        } catch let error as NoSuchProviderReferenceError {
            #expect(error.provider == "openai")
            #expect(error.reference == reference)
            #expect(NoSuchProviderReferenceError.isInstance(error))
        }

        do {
            _ = try resolveProviderReference(reference: [:], provider: "openai")
            Issue.record("Expected NoSuchProviderReferenceError")
        } catch let error as NoSuchProviderReferenceError {
            #expect(error.provider == "openai")
            #expect(error.reference == [:])
            #expect(NoSuchProviderReferenceError.isInstance(error))
        }
    }
}
