import Testing
import Foundation
import SwiftAISDK
import AISDKProvider

@Suite("MCP Apps")
struct MCPAppsTests {
    @Test("Reading app HTML normalizes security metadata and detects permission drift")
    func readAndFingerprint() async throws {
        let uri = "ui://app/main"
        let client = try await createMCPClient(config: .init(transport: .custom(MockMCPTransport(resourceContents: [
            .blob(uri: uri, name: nil, title: nil, mimeType: MCP_APP_MIME_TYPE,
                  blob: Data("<main>Hello</main>".utf8).base64EncodedString(), meta: ["ui": .object([
                    "prefersBorder": .string("invalid"),
                    "csp": .object(["connectDomains": .array([.string("https://api.example.com"), .number(1)])]),
                    "permissions": .object(["camera": .object([:])]),
                  ])]),
        ]))))
        let resource = try await readMCPAppResource(client: client, uri: uri)
        #expect(resource.html == "<main>Hello</main>")
        #expect(resource.meta == [
            "csp": .object(["connectDomains": .array([.string("https://api.example.com")])]),
            "permissions": .object(["camera": .object([:])]),
        ])
        let baseline = try fingerprintMCPAppResource(resource)
        #expect(baseline == "rTublRnku0eGYc2KVp0QE-tns63C3WW1mhS58t6VxqI")
        let changed = MCPAppResource(uri: uri, html: resource.html, meta: [
            "csp": .object(["connectDomains": .array([.string("https://api.example.com")])]),
            "permissions": .object(["microphone": .object([:])]),
        ])
        #expect(try detectMCPAppResourceDrift(current: fingerprintMCPAppResource(changed), baseline: baseline))
        try await client.close()
    }

    @Test("Tool visibility separates model and app tools and accepts legacy resource URIs")
    func visibility() throws {
        let schema: JSONValue = .object([:])
        let definitions = ListToolsResult(tools: [
            .init(name: "default", inputSchema: schema),
            .init(name: "malformed", inputSchema: schema, meta: ["ui": .object(["visibility": .number(1)])]),
            .init(name: "app-only", inputSchema: schema, meta: ["ui": .object(["visibility": .array([.string("app"), .number(7)])])]),
            .init(name: "both", inputSchema: schema, meta: ["ui": .object(["visibility": .array([.string("app"), .string("model")])])]),
        ], nextCursor: "next")
        let result = try splitMCPAppTools(definitions)
        #expect(result.modelVisible.tools.map(\.name) == ["default", "malformed", "both"])
        #expect(result.appVisible.tools.map(\.name) == ["app-only", "both"])
        #expect(result.appVisible.nextCursor == "next")
        #expect(try getMCPAppToolMeta(meta: ["ui/resourceUri": .string("ui://legacy")])?["resourceUri"] == .string("ui://legacy"))
        #expect(throws: MCPClientError.self) { try getMCPAppToolMeta(meta: ["ui": .object(["resourceUri": .string("https://untrusted")])]) }
    }
}
