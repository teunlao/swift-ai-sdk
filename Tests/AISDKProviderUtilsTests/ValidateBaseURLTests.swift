import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("validateBaseURL")
struct ValidateBaseURLTests {
    @Test("preserves configured and absent base URLs")
    func preservesConfiguredAndAbsentBaseURLs() throws {
        #expect(try validateBaseURL("https://example.com/") == "https://example.com/")
        #expect(try validateBaseURL(nil) == nil)
    }

    @Test("rejects empty and whitespace-only base URLs", arguments: ["", " ", "\n\t"])
    func rejectsEmptyBaseURLs(_ baseURL: String) {
        do {
            _ = try validateBaseURL(baseURL)
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "baseURL")
            #expect(error.message == "baseURL must be a non-empty string.")
        } catch {
            Issue.record("Expected InvalidArgumentError, got \(error)")
        }
    }
}
