import Foundation
import AISDKProvider

public let MCP_APP_EXTENSION_NAME = "io.modelcontextprotocol/ui"
public let MCP_APP_MIME_TYPE = "text/html;profile=mcp-app"
public let MCP_APP_LEGACY_RESOURCE_URI_META_KEY = "ui/resourceUri"
public let mcpAppClientCapabilities = ClientCapabilities(extensions: [
    MCP_APP_EXTENSION_NAME: .object(["mimeTypes": .array([.string(MCP_APP_MIME_TYPE)])]),
])

public typealias MCPAppResourceCSP = [String: JSONValue]
public typealias MCPAppResourceMeta = [String: JSONValue]
public typealias MCPAppToolMeta = [String: JSONValue]

public struct MCPAppResource: Sendable {
    public let uri: String
    public let mimeType: String = MCP_APP_MIME_TYPE
    public let html: String
    public let meta: MCPAppResourceMeta?

    public init(uri: String, html: String, meta: MCPAppResourceMeta? = nil) {
        self.uri = uri
        self.html = html
        self.meta = meta
    }
}

public func getMCPAppToolMeta(meta: ToolMeta?) throws -> MCPAppToolMeta? {
    let ui: [String: JSONValue]?
    if case .object(let object) = meta?["ui"] { ui = object } else { ui = nil }
    var result = ui ?? [:]
    let nestedUri = ui?["resourceUri"]
    let resourceUri = nestedUri == .null ? meta?[MCP_APP_LEGACY_RESOURCE_URI_META_KEY] : nestedUri ?? meta?[MCP_APP_LEGACY_RESOURCE_URI_META_KEY]
    if let resourceUri {
        guard case .string(let uri) = resourceUri, uri.hasPrefix("ui://") else {
            throw MCPClientError(message: "Invalid MCP App resource URI: \(mcpJSONString(resourceUri))")
        }
        result["resourceUri"] = resourceUri
    } else if ui == nil {
        return nil
    }
    if case .array(let visibility) = ui?["visibility"] {
        result["visibility"] = .array(visibility.filter { $0 == .string("model") || $0 == .string("app") })
    }
    return result
}

public enum MCPAppToolVisibility: String, Sendable { case model, app }

public func getMCPAppToolMeta(_ tool: MCPTool) throws -> MCPAppToolMeta? {
    try getMCPAppToolMeta(meta: tool.meta)
}

public func getMCPAppResourceUri(_ tool: MCPTool) throws -> String? {
    if case .string(let uri) = try getMCPAppToolMeta(tool)?["resourceUri"] { return uri }
    return nil
}

public func isMCPAppTool(_ tool: MCPTool) throws -> Bool { try getMCPAppResourceUri(tool) != nil }

public func getMCPAppResourceUris(_ definitions: ListToolsResult) throws -> [String] {
    var uris: [String] = []
    for tool in definitions.tools {
        if let uri = try getMCPAppResourceUri(tool), !uris.contains(uri) { uris.append(uri) }
    }
    return uris
}

public func splitMCPAppTools(_ definitions: ListToolsResult) throws -> (modelVisible: ListToolsResult, appVisible: ListToolsResult) {
    var model: [MCPTool] = []
    var app: [MCPTool] = []
    for tool in definitions.tools {
        let meta = try getMCPAppToolMeta(meta: tool.meta)
        let visibility: [JSONValue]?
        if case .array(let array) = meta?["visibility"] { visibility = array } else { visibility = nil }
        if visibility == nil || visibility!.contains(.string("model")) { model.append(tool) }
        if visibility?.contains(.string("app")) == true { app.append(tool) }
    }
    return (
        ListToolsResult(tools: model, nextCursor: definitions.nextCursor, meta: definitions.meta),
        ListToolsResult(tools: app, nextCursor: definitions.nextCursor, meta: definitions.meta)
    )
}

public func getMCPAppResourceFromReadResult(uri: String, resource: ReadResourceResult) throws -> MCPAppResource {
    for content in resource.contents {
        let contentUri: String
        let mimeType: String?
        let html: String
        let meta: JSONValue?
        switch content {
        case .text(let value, _, _, let type, let text, let metadata, _):
            contentUri = value; mimeType = type; html = text; meta = metadata
        case .blob(let value, _, _, let type, let blob, let metadata, _):
            guard value == uri else { continue }
            contentUri = value; mimeType = type; meta = metadata
            guard let data = Data(base64Encoded: blob) else {
                throw MCPClientError(message: "Unsupported MCP App resource content format: \(uri)")
            }
            html = String(decoding: data, as: UTF8.self)
        }
        guard contentUri == uri else { continue }
        guard mimeType == MCP_APP_MIME_TYPE else {
            throw MCPClientError(message: "Unsupported MCP App resource MIME type: \(mimeType ?? "undefined")")
        }
        var ui: [String: JSONValue]?
        if case .object(let resourceMeta) = meta, case .object(let raw) = resourceMeta["ui"] {
            var parsed = raw
            if let border = parsed["prefersBorder"], case .bool = border {} else { parsed.removeValue(forKey: "prefersBorder") }
            if case .object(var csp) = parsed["csp"] {
                for key in ["connectDomains", "resourceDomains", "frameDomains"] {
                    if case .array(let values) = csp[key] {
                        csp[key] = .array(values.filter { if case .string = $0 { true } else { false } })
                    } else { csp.removeValue(forKey: key) }
                }
                parsed["csp"] = .object(csp)
            } else { parsed.removeValue(forKey: "csp") }
            if case .object = parsed["permissions"] {} else { parsed.removeValue(forKey: "permissions") }
            ui = parsed
        }
        return MCPAppResource(uri: uri, html: html, meta: ui)
    }
    throw MCPClientError(message: "MCP App resource not found in read result: \(uri)")
}

public func readMCPAppResource(client: any MCPClient, uri: String, options: RequestOptions? = nil) async throws -> MCPAppResource {
    guard uri.hasPrefix("ui://") else {
        throw MCPClientError(message: "Unsupported MCP App resource URI: \(uri)")
    }
    return try getMCPAppResourceFromReadResult(uri: uri, resource: await client.readResource(args: .init(uri: uri, options: options)))
}

public func fingerprintMCPAppResource(_ resource: MCPAppResource) throws -> String {
    let value: JSONValue = .object([
        "html": .string(resource.html),
        "csp": resource.meta?["csp"] ?? .null,
        "permissions": resource.meta?["permissions"] ?? .null,
    ])
    return try hashCanonical(value)
}

public func detectMCPAppResourceDrift(current: String, baseline: String) -> Bool { current != baseline }

private func mcpJSONString(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? "null"
}
