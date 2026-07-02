import Testing
@testable import AISDKProviderUtils

@Suite("withoutTrailingSlash")
struct WithoutTrailingSlashTests {
    @Test("removes a single trailing slash")
    func removesSingleTrailingSlash() {
        #expect(withoutTrailingSlash("https://api.example.com/v1/") == "https://api.example.com/v1")
    }

    @Test("leaves values without a trailing slash unchanged")
    func leavesValuesWithoutTrailingSlashUnchanged() {
        #expect(withoutTrailingSlash("https://api.example.com/v1") == "https://api.example.com/v1")
    }

    @Test("only removes the final slash")
    func onlyRemovesFinalSlash() {
        #expect(withoutTrailingSlash("https://api.example.com/v1//") == "https://api.example.com/v1/")
    }

    @Test("preserves slash before query because it is not trailing")
    func preservesSlashBeforeQuery() {
        #expect(withoutTrailingSlash("https://api.example.com/v1/?api-version=1") == "https://api.example.com/v1/?api-version=1")
    }

    @Test("returns nil for nil input")
    func returnsNilForNilInput() {
        #expect(withoutTrailingSlash(nil) == nil)
    }
}
