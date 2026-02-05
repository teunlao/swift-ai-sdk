/**
 Tests for OAuth URL utilities.
 
 Port of `packages/mcp/src/util/oauth.util.test.ts`.
 */

import Foundation
import Testing

@testable import SwiftAISDK

@Suite("OAuthUtil")
struct OAuthUtilTests {

    // MARK: - resourceUrlFromServerUrl

    @Test("resourceUrlFromServerUrl: should remove fragments")
    func resourceUrlFromServerUrlRemovesFragments() throws {
        let url1 = try #require(URL(string: "https://example.com/path#fragment"))
        #expect(resourceUrlFromServerUrl(url1).absoluteString == "https://example.com/path")

        let url2 = try #require(URL(string: "https://example.com#fragment"))
        #expect(resourceUrlFromServerUrl(url2).absoluteString == "https://example.com/")

        let url3 = try #require(URL(string: "https://example.com/path?query=1#fragment"))
        #expect(resourceUrlFromServerUrl(url3).absoluteString == "https://example.com/path?query=1")
    }

    @Test("resourceUrlFromServerUrl: should return URL unchanged if no fragment")
    func resourceUrlFromServerUrlNoFragment() throws {
        let url1 = try #require(URL(string: "https://example.com"))
        #expect(resourceUrlFromServerUrl(url1).absoluteString == "https://example.com/")

        let url2 = try #require(URL(string: "https://example.com/path"))
        #expect(resourceUrlFromServerUrl(url2).absoluteString == "https://example.com/path")

        let url3 = try #require(URL(string: "https://example.com/path?query=1"))
        #expect(resourceUrlFromServerUrl(url3).absoluteString == "https://example.com/path?query=1")
    }

    @Test("resourceUrlFromServerUrl: should keep everything else unchanged")
    func resourceUrlFromServerUrlKeepsOtherComponents() throws {
        // Case sensitivity preserved (path); host normalized to lowercase like JavaScript URLs.
        let url1 = try #require(URL(string: "https://EXAMPLE.COM/PATH"))
        #expect(resourceUrlFromServerUrl(url1).absoluteString == "https://example.com/PATH")

        // Ports preserved (default ports are normalized away in JavaScript URL serialization).
        let url2 = try #require(URL(string: "https://example.com:443/path"))
        #expect(resourceUrlFromServerUrl(url2).absoluteString == "https://example.com/path")

        let url3 = try #require(URL(string: "https://example.com:8080/path"))
        #expect(resourceUrlFromServerUrl(url3).absoluteString == "https://example.com:8080/path")

        // Query parameters preserved.
        let url4 = try #require(URL(string: "https://example.com?foo=bar&baz=qux"))
        #expect(resourceUrlFromServerUrl(url4).absoluteString == "https://example.com/?foo=bar&baz=qux")

        // Trailing slashes preserved.
        let url5 = try #require(URL(string: "https://example.com/"))
        #expect(resourceUrlFromServerUrl(url5).absoluteString == "https://example.com/")

        let url6 = try #require(URL(string: "https://example.com/path/"))
        #expect(resourceUrlFromServerUrl(url6).absoluteString == "https://example.com/path/")
    }

    // MARK: - checkResourceAllowed

    @Test("checkResourceAllowed: should match identical URLs")
    func checkResourceAllowedIdenticalURLs() throws {
        #expect(
            checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/path")),
                configuredResource: try #require(URL(string: "https://example.com/path"))
            )
        )

        #expect(
            checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/")),
                configuredResource: try #require(URL(string: "https://example.com/"))
            )
        )
    }

    @Test("checkResourceAllowed: should not match URLs with different paths")
    func checkResourceAllowedDifferentPaths() throws {
        #expect(
            !checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/path1")),
                configuredResource: try #require(URL(string: "https://example.com/path2"))
            )
        )

        #expect(
            !checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/")),
                configuredResource: try #require(URL(string: "https://example.com/path"))
            )
        )
    }

    @Test("checkResourceAllowed: should not match URLs with different domains")
    func checkResourceAllowedDifferentDomains() throws {
        #expect(
            !checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/path")),
                configuredResource: try #require(URL(string: "https://example.org/path"))
            )
        )
    }

    @Test("checkResourceAllowed: should not match URLs with different ports")
    func checkResourceAllowedDifferentPorts() throws {
        #expect(
            !checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com:8080/path")),
                configuredResource: try #require(URL(string: "https://example.com/path"))
            )
        )
    }

    @Test("checkResourceAllowed: should not match URLs where one path is a sub-path of another")
    func checkResourceAllowedSubpaths() throws {
        #expect(
            !checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/mcpxxxx")),
                configuredResource: try #require(URL(string: "https://example.com/mcp"))
            )
        )

        #expect(
            !checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/folder")),
                configuredResource: try #require(URL(string: "https://example.com/folder/subfolder"))
            )
        )

        #expect(
            checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/api/v1")),
                configuredResource: try #require(URL(string: "https://example.com/api"))
            )
        )
    }

    @Test("checkResourceAllowed: should handle trailing slashes vs no trailing slashes")
    func checkResourceAllowedTrailingSlashes() throws {
        #expect(
            checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/mcp/")),
                configuredResource: try #require(URL(string: "https://example.com/mcp"))
            )
        )

        #expect(
            !checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com/folder")),
                configuredResource: try #require(URL(string: "https://example.com/folder/"))
            )
        )
    }

    @Test("checkResourceAllowed: treats default ports as equivalent")
    func checkResourceAllowedDefaultPortsEquivalent() throws {
        #expect(
            checkResourceAllowed(
                requestedResource: try #require(URL(string: "https://example.com:443/mcp")),
                configuredResource: try #require(URL(string: "https://example.com/mcp"))
            )
        )
    }
}

