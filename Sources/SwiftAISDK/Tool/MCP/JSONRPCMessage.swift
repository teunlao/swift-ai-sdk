/**
 JSON-RPC 2.0 message types for Model Context Protocol.

 Port of `@ai-sdk/ai/src/tool/mcp/json-rpc-message.ts`.

 This module defines the JSON-RPC 2.0 message format used by MCP, including
 requests, responses, errors, and notifications.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Constants

/// JSON-RPC version constant
public let jsonrpcVersion = "2.0"

// MARK: - Request ID

/// JSON-RPC request/response ID (can be string or integer)
public enum JSONRPCID: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "ID must be either a string or an integer"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

// MARK: - JSON-RPC Request

/// JSON-RPC 2.0 request
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let method: String
    public let params: JSONValue?

    public init(jsonrpc: String = jsonrpcVersion, id: JSONRPCID, method: String, params: JSONValue? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

// MARK: - JSON-RPC Response

/// JSON-RPC 2.0 successful response
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let result: JSONValue

    public init(id: JSONRPCID, result: JSONValue) {
        self.jsonrpc = jsonrpcVersion
        self.id = id
        self.result = result
    }
}

// MARK: - JSON-RPC Error

/// JSON-RPC 2.0 error object
public struct JSONRPCErrorObject: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// JSON-RPC 2.0 error response
public struct JSONRPCError: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let error: JSONRPCErrorObject

    public init(id: JSONRPCID, error: JSONRPCErrorObject) {
        self.jsonrpc = jsonrpcVersion
        self.id = id
        self.error = error
    }
}

// MARK: - JSON-RPC Notification

/// JSON-RPC 2.0 notification (request without ID, no response expected)
public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: JSONValue?

    public init(jsonrpc: String = jsonrpcVersion, method: String, params: JSONValue? = nil) {
        self.jsonrpc = jsonrpc
        self.method = method
        self.params = params
    }
}

// MARK: - JSON-RPC Message Union

/// Union of all JSON-RPC message types
public enum JSONRPCMessage: Codable, Sendable {
    case request(JSONRPCRequest)
    case notification(JSONRPCNotification)
    case response(JSONRPCResponse)
    case error(JSONRPCError)

    enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
        case result
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Verify jsonrpc version
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == jsonrpcVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc,
                in: container,
                debugDescription: "Expected JSON-RPC version \(jsonrpcVersion), got \(version)"
            )
        }

        // Check if message has an ID (request, response, or error)
        if let id = try? container.decode(JSONRPCID.self, forKey: .id) {
            // Has ID - could be request, response, or error
            if container.contains(.result) {
                // Response
                let result = try container.decode(JSONValue.self, forKey: .result)
                self = .response(JSONRPCResponse(id: id, result: result))
            } else if container.contains(.error) {
                // Error
                let error = try container.decode(JSONRPCErrorObject.self, forKey: .error)
                self = .error(JSONRPCError(id: id, error: error))
            } else if container.contains(.method) {
                // Request
                let method = try container.decode(String.self, forKey: .method)
                let params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
                self = .request(JSONRPCRequest(id: id, method: method, params: params))
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .method,
                    in: container,
                    debugDescription: "Message with ID must have either 'method', 'result', or 'error'"
                )
            }
        } else {
            // No ID - must be notification
            let method = try container.decode(String.self, forKey: .method)
            let params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
            self = .notification(JSONRPCNotification(method: method, params: params))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let request):
            try request.encode(to: encoder)
        case .notification(let notification):
            try notification.encode(to: encoder)
        case .response(let response):
            try response.encode(to: encoder)
        case .error(let error):
            try error.encode(to: encoder)
        }
    }
}
