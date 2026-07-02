import Testing
@testable import AISDKProviderUtils

@Suite("isSameOrigin")
struct IsSameOriginTests {
    @Test("returns true for identical origins ignoring path and query")
    func identicalOrigins() {
        #expect(isSameOrigin("https://api.example.com/v1/file", "https://api.example.com"))
        #expect(isSameOrigin("https://api.example.com/a?x=1", "https://api.example.com/b"))
    }

    @Test("returns false for different host")
    func differentHost() {
        #expect(!isSameOrigin("https://cdn.evil.com/file", "https://api.example.com"))
    }

    @Test("returns false for different scheme or port")
    func differentSchemeOrPort() {
        #expect(!isSameOrigin("http://api.example.com/file", "https://api.example.com"))
        #expect(!isSameOrigin("https://api.example.com:8443/file", "https://api.example.com"))
    }

    @Test("normalizes default ports like URL.origin")
    func normalizesDefaultPorts() {
        #expect(isSameOrigin("https://api.example.com:443/file", "https://api.example.com"))
        #expect(isSameOrigin("http://api.example.com:80/file", "http://api.example.com"))
    }

    @Test("fails closed on invalid input")
    func failsClosedOnInvalidInput() {
        #expect(!isSameOrigin("not-a-url", "https://api.example.com"))
        #expect(!isSameOrigin("https://api.example.com/file", "not-a-url"))
    }
}
