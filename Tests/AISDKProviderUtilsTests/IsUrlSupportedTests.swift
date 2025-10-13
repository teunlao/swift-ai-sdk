import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for isUrlSupported function.

 Port of `@ai-sdk/provider-utils/src/is-url-supported.test.ts`.
 */
@Suite("IsUrlSupported")
struct IsUrlSupportedTests {
    // Helper function to create NSRegularExpression from pattern string
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    @Suite("No URLs supported")
    struct NoUrlsSupported {
        @Test("returns false when model does not support any URLs")
        func returnsFalse() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://example.com",
                supportedUrls: [:]
            )
            #expect(result == false)
        }
    }

    @Suite("Specific media types and URLs")
    struct SpecificMediaTypes {
        @Test("returns true for exact media type and exact URL match")
        func exactMediaTypeAndUrl() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://example.com",
                supportedUrls: [
                    "text/plain": [regex("https://example\\.com")]
                ]
            )
            #expect(result == true)
        }

        @Test("returns true for exact media type and regex URL match")
        func exactMediaTypeAndRegexUrl() {
            let result = isUrlSupported(
                mediaType: "image/png",
                url: "https://images.example.com/cat.png",
                supportedUrls: [
                    "image/png": [regex("https://images\\.example\\.com/.+")]
                ]
            )
            #expect(result == true)
        }

        @Test("returns true for exact media type and one of multiple regex URLs match")
        func exactMediaTypeAndMultipleUrls() {
            let result = isUrlSupported(
                mediaType: "image/png",
                url: "https://another.com/img.png",
                supportedUrls: [
                    "image/png": [
                        regex("https://images\\.example\\.com/.+"),
                        regex("https://another\\.com/img\\.png")
                    ]
                ]
            )
            #expect(result == true)
        }

        @Test("returns false for exact media type but URL mismatch")
        func exactMediaTypeButUrlMismatch() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://another.com",
                supportedUrls: [
                    "text/plain": [regex("https://example\\.com")]
                ]
            )
            #expect(result == false)
        }

        @Test("returns false for URL match but media type mismatch")
        func urlMatchButMediaTypeMismatch() {
            let result = isUrlSupported(
                mediaType: "image/png", // Different media type
                url: "https://example.com",
                supportedUrls: [
                    "text/plain": [regex("https://example\\.com")]
                ]
            )
            #expect(result == false)
        }
    }

    @Suite("Wildcard media type (*)")
    struct WildcardMediaType {
        @Test("returns true for wildcard media type and exact URL match")
        func wildcardMediaTypeAndExactUrl() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://example.com",
                supportedUrls: [
                    "*": [regex("https://example\\.com")]
                ]
            )
            #expect(result == true)
        }

        @Test("returns true for wildcard media type and regex URL match")
        func wildcardMediaTypeAndRegexUrl() {
            let result = isUrlSupported(
                mediaType: "image/jpeg",
                url: "https://images.example.com/dog.jpg",
                supportedUrls: [
                    "*": [regex("https://images\\.example\\.com/.+")]
                ]
            )
            #expect(result == true)
        }

        @Test("returns false for wildcard media type but URL mismatch")
        func wildcardMediaTypeButUrlMismatch() {
            let result = isUrlSupported(
                mediaType: "video/mp4",
                url: "https://another.com",
                supportedUrls: [
                    "*": [regex("https://example\\.com")]
                ]
            )
            #expect(result == false)
        }
    }

    @Suite("Both specific and wildcard media types")
    struct BothSpecificAndWildcard {
        private static let supportedUrls: [String: [NSRegularExpression]] = [
            "text/plain": [regex("https://text\\.com")],
            "*": [regex("https://any\\.com")]
        ]

        @Test("returns true if URL matches under specific media type")
        func urlMatchesSpecificMediaType() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://text.com",
                supportedUrls: Self.supportedUrls
            )
            #expect(result == true)
        }

        @Test("returns true if URL matches under wildcard media type even if specific exists")
        func urlMatchesWildcardEvenIfSpecificExists() {
            let result = isUrlSupported(
                mediaType: "text/plain", // Specific type exists
                url: "https://any.com", // Matches wildcard
                supportedUrls: Self.supportedUrls
            )
            #expect(result == true)
        }

        @Test("returns true if URL matches under wildcard for a non-specified media type")
        func urlMatchesWildcardForNonSpecifiedMediaType() {
            let result = isUrlSupported(
                mediaType: "image/png", // No specific entry for this type
                url: "https://any.com", // Matches wildcard
                supportedUrls: Self.supportedUrls
            )
            #expect(result == true)
        }

        @Test("returns false if URL matches neither specific nor wildcard")
        func urlMatchesNeitherSpecificNorWildcard() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://other.com",
                supportedUrls: Self.supportedUrls
            )
            #expect(result == false)
        }

        @Test("returns false if URL does not match wildcard for a non-specified media type")
        func urlDoesNotMatchWildcardForNonSpecifiedMediaType() {
            let result = isUrlSupported(
                mediaType: "image/png",
                url: "https://other.com",
                supportedUrls: Self.supportedUrls
            )
            #expect(result == false)
        }
    }

    @Suite("Edge cases")
    struct EdgeCases {
        @Test("returns true if an empty URL matches a pattern")
        func emptyUrlMatchesPattern() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "",
                supportedUrls: [
                    "text/plain": [regex(".*")] // Matches any string, including empty
                ]
            )
            #expect(result == true)
        }

        @Test("returns false if an empty URL does not match a pattern")
        func emptyUrlDoesNotMatchPattern() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "",
                supportedUrls: [
                    "text/plain": [regex("https://.+")] // Requires non-empty string
                ]
            )
            #expect(result == false)
        }
    }

    @Suite("Case sensitivity")
    struct CaseSensitivity {
        @Test("is case-insensitive for media types")
        func caseInsensitiveForMediaTypes() {
            let result = isUrlSupported(
                mediaType: "TEXT/PLAIN", // Uppercase
                url: "https://example.com",
                supportedUrls: [
                    "text/plain": [regex("https://example\\.com")] // Lowercase
                ]
            )
            #expect(result == true)
        }

        @Test("handles case-insensitive regex for URLs if specified")
        func caseInsensitiveForUrls() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://EXAMPLE.com/path", // Uppercase domain
                supportedUrls: [
                    "text/plain": [regex("https://example\\.com/path")]
                ]
            )
            #expect(result == true)
        }

        @Test("is case-insensitive for URL paths by default regex")
        func caseInsensitiveForUrlPaths() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://example.com/PATH", // Uppercase path
                supportedUrls: [
                    "text/plain": [regex("https://example\\.com/path")] // Lowercase path in regex
                ]
            )
            #expect(result == true)
        }
    }

    @Suite("Wildcard subtypes in media types")
    struct WildcardSubtypes {
        @Test("returns true for wildcard subtype match")
        func wildcardSubtypeMatch() {
            let result = isUrlSupported(
                mediaType: "image/png",
                url: "https://example.com",
                supportedUrls: [
                    "image/*": [regex("https://example\\.com")]
                ]
            )
            #expect(result == true)
        }

        @Test("uses full wildcard if subtype wildcard is not matched or supported")
        func usesFullWildcardIfSubtypeNotMatched() {
            let result = isUrlSupported(
                mediaType: "image/png",
                url: "https://any.com",
                supportedUrls: [
                    "image/*": [regex("https://images\\.com")], // Doesn't match URL
                    "*": [regex("https://any\\.com")] // Matches URL
                ]
            )
            #expect(result == true)
        }
    }

    @Suite("Empty URL arrays for a media type")
    struct EmptyUrlArrays {
        @Test("returns false if the specific media type has an empty URL array")
        func specificMediaTypeHasEmptyArray() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://example.com",
                supportedUrls: [
                    "text/plain": []
                ]
            )
            #expect(result == false)
        }

        @Test("falls back to wildcard if specific media type has empty array but wildcard matches")
        func fallsBackToWildcardIfSpecificHasEmptyArray() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://any.com",
                supportedUrls: [
                    "text/plain": [],
                    "*": [regex("https://any\\.com")]
                ]
            )
            #expect(result == true)
        }

        @Test("returns false if specific media type has empty array and wildcard does not match")
        func specificHasEmptyArrayAndWildcardDoesNotMatch() {
            let result = isUrlSupported(
                mediaType: "text/plain",
                url: "https://another.com",
                supportedUrls: [
                    "text/plain": [],
                    "*": [regex("https://any\\.com")]
                ]
            )
            #expect(result == false)
        }
    }
}
