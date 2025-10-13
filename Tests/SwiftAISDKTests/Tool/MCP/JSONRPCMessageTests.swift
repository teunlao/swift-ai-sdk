/**
 Tests for JSON-RPC 2.0 message types encoding/decoding.

 Tests all JSON-RPC message types and their encoding/decoding logic to ensure
 100% parity with upstream TypeScript behavior.
 */

import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("JSON-RPC Message Types")
struct JSONRPCMessageTests {

    // MARK: - Constants Tests

    @Test("JSON-RPC version constant")
    func testJsonrpcVersion() {
        #expect(jsonrpcVersion == "2.0")
    }

    // MARK: - JSONRPCID Tests

    @Test("JSONRPCID string encoding/decoding")
    func testJSONRPCIDString() throws {
        let id = JSONRPCID.string("request-123")

        let encoded = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(JSONRPCID.self, from: encoded)

        #expect(decoded == .string("request-123"))
    }

    @Test("JSONRPCID int encoding/decoding")
    func testJSONRPCIDInt() throws {
        let id = JSONRPCID.int(42)

        let encoded = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(JSONRPCID.self, from: encoded)

        #expect(decoded == .int(42))
    }

    @Test("JSONRPCID string from JSON")
    func testJSONRPCIDStringFromJSON() throws {
        let json = "\"abc-123\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONRPCID.self, from: json)

        #expect(decoded == .string("abc-123"))
    }

    @Test("JSONRPCID int from JSON")
    func testJSONRPCIDIntFromJSON() throws {
        let json = "123".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONRPCID.self, from: json)

        #expect(decoded == .int(123))
    }

    @Test("JSONRPCID negative int")
    func testJSONRPCIDNegativeInt() throws {
        let id = JSONRPCID.int(-1)

        let encoded = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(JSONRPCID.self, from: encoded)

        #expect(decoded == .int(-1))
    }

    // MARK: - JSONRPCRequest Tests

    @Test("JSONRPCRequest with string ID and params")
    func testJSONRPCRequestWithParams() throws {
        let request = JSONRPCRequest(
            id: .string("req-1"),
            method: "tools/list",
            params: BaseParams(meta: ["cursor": .string("abc")])
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: encoded)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .string("req-1"))
        #expect(decoded.method == "tools/list")
        #expect(decoded.params?.meta?["cursor"] == .string("abc"))
    }

    @Test("JSONRPCRequest with int ID without params")
    func testJSONRPCRequestWithoutParams() throws {
        let request = JSONRPCRequest(id: .int(1), method: "initialize")

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: encoded)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.method == "initialize")
        #expect(decoded.params == nil)
    }

    @Test("JSONRPCRequest JSON format")
    func testJSONRPCRequestJSONFormat() throws {
        let request = JSONRPCRequest(id: .int(1), method: "test")
        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["jsonrpc"] as? String == "2.0")
        #expect(json["id"] as? Int == 1)
        #expect(json["method"] as? String == "test")
    }

    @Test("JSONRPCRequest from JSON")
    func testJSONRPCRequestFromJSON() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "req-123",
            "method": "tools/call",
            "params": {
                "_meta": {"key": "value"}
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: json)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .string("req-123"))
        #expect(decoded.method == "tools/call")
        #expect(decoded.params != nil)
    }

    // MARK: - JSONRPCResponse Tests

    @Test("JSONRPCResponse encoding/decoding")
    func testJSONRPCResponseCoding() throws {
        let response = JSONRPCResponse(
            id: .string("req-1"),
            result: .object(["status": .string("success")])
        )

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: encoded)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .string("req-1"))
        if case .object(let obj) = decoded.result {
            #expect(obj["status"] == .string("success"))
        } else {
            Issue.record("Expected object result")
        }
    }

    @Test("JSONRPCResponse with null result")
    func testJSONRPCResponseWithNullResult() throws {
        let response = JSONRPCResponse(id: .int(1), result: .null)

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: encoded)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.result == .null)
    }

    @Test("JSONRPCResponse with array result")
    func testJSONRPCResponseWithArrayResult() throws {
        let response = JSONRPCResponse(
            id: .int(2),
            result: .array([.string("a"), .string("b"), .number(3)])
        )

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: encoded)

        if case .array(let arr) = decoded.result {
            #expect(arr.count == 3)
            #expect(arr[0] == .string("a"))
            #expect(arr[1] == .string("b"))
            #expect(arr[2] == .number(3))
        } else {
            Issue.record("Expected array result")
        }
    }

    @Test("JSONRPCResponse from JSON")
    func testJSONRPCResponseFromJSON() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 42,
            "result": {"data": "test"}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: json)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(42))
    }

    // MARK: - JSONRPCError Tests

    @Test("JSONRPCError encoding/decoding")
    func testJSONRPCErrorCoding() throws {
        let error = JSONRPCError(
            id: .string("req-1"),
            error: JSONRPCErrorObject(
                code: -32600,
                message: "Invalid Request",
                data: .string("Additional error info")
            )
        )

        let encoded = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(JSONRPCError.self, from: encoded)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .string("req-1"))
        #expect(decoded.error.code == -32600)
        #expect(decoded.error.message == "Invalid Request")
        #expect(decoded.error.data == .string("Additional error info"))
    }

    @Test("JSONRPCError without data field")
    func testJSONRPCErrorWithoutData() throws {
        let error = JSONRPCError(
            id: .int(1),
            error: JSONRPCErrorObject(code: -32601, message: "Method not found")
        )

        let encoded = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(JSONRPCError.self, from: encoded)

        #expect(decoded.error.code == -32601)
        #expect(decoded.error.message == "Method not found")
        #expect(decoded.error.data == nil)
    }

    @Test("JSONRPCError standard error codes")
    func testJSONRPCErrorStandardCodes() throws {
        // Test standard JSON-RPC 2.0 error codes
        let parseError = JSONRPCErrorObject(code: -32700, message: "Parse error")
        let invalidRequest = JSONRPCErrorObject(code: -32600, message: "Invalid Request")
        let methodNotFound = JSONRPCErrorObject(code: -32601, message: "Method not found")
        let invalidParams = JSONRPCErrorObject(code: -32602, message: "Invalid params")
        let internalError = JSONRPCErrorObject(code: -32603, message: "Internal error")

        #expect(parseError.code == -32700)
        #expect(invalidRequest.code == -32600)
        #expect(methodNotFound.code == -32601)
        #expect(invalidParams.code == -32602)
        #expect(internalError.code == -32603)
    }

    @Test("JSONRPCError from JSON")
    func testJSONRPCErrorFromJSON() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "req-456",
            "error": {
                "code": -32602,
                "message": "Invalid params",
                "data": {"expected": "string", "got": "number"}
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCError.self, from: json)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .string("req-456"))
        #expect(decoded.error.code == -32602)
        #expect(decoded.error.message == "Invalid params")
        #expect(decoded.error.data != nil)
    }

    // MARK: - JSONRPCNotification Tests

    @Test("JSONRPCNotification with params")
    func testJSONRPCNotificationWithParams() throws {
        let notification = JSONRPCNotification(
            method: "progress",
            params: BaseParams(meta: ["percent": .number(50)])
        )

        let encoded = try JSONEncoder().encode(notification)
        let decoded = try JSONDecoder().decode(JSONRPCNotification.self, from: encoded)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.method == "progress")
        #expect(decoded.params?.meta?["percent"] == .number(50))
    }

    @Test("JSONRPCNotification without params")
    func testJSONRPCNotificationWithoutParams() throws {
        let notification = JSONRPCNotification(method: "cancelled")

        let encoded = try JSONEncoder().encode(notification)
        let decoded = try JSONDecoder().decode(JSONRPCNotification.self, from: encoded)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.method == "cancelled")
        #expect(decoded.params == nil)
    }

    @Test("JSONRPCNotification has no ID field")
    func testJSONRPCNotificationNoID() throws {
        let notification = JSONRPCNotification(method: "test")
        let encoded = try JSONEncoder().encode(notification)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["id"] == nil)
        #expect(json["jsonrpc"] as? String == "2.0")
        #expect(json["method"] as? String == "test")
    }

    @Test("JSONRPCNotification from JSON")
    func testJSONRPCNotificationFromJSON() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "method": "notification",
            "params": {}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCNotification.self, from: json)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.method == "notification")
    }

    // MARK: - JSONRPCMessage Union Tests

    @Test("JSONRPCMessage decodes request correctly")
    func testJSONRPCMessageDecodesRequest() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "test"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCMessage.self, from: json)

        if case .request(let request) = decoded {
            #expect(request.id == .int(1))
            #expect(request.method == "test")
        } else {
            Issue.record("Expected request variant")
        }
    }

    @Test("JSONRPCMessage decodes response correctly")
    func testJSONRPCMessageDecodesResponse() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "req-1",
            "result": {"status": "ok"}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCMessage.self, from: json)

        if case .response(let response) = decoded {
            #expect(response.id == .string("req-1"))
        } else {
            Issue.record("Expected response variant")
        }
    }

    @Test("JSONRPCMessage decodes error correctly")
    func testJSONRPCMessageDecodesError() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 2,
            "error": {
                "code": -32600,
                "message": "Invalid Request"
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCMessage.self, from: json)

        if case .error(let error) = decoded {
            #expect(error.id == .int(2))
            #expect(error.error.code == -32600)
        } else {
            Issue.record("Expected error variant")
        }
    }

    @Test("JSONRPCMessage decodes notification correctly")
    func testJSONRPCMessageDecodesNotification() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "method": "notify"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCMessage.self, from: json)

        if case .notification(let notification) = decoded {
            #expect(notification.method == "notify")
        } else {
            Issue.record("Expected notification variant")
        }
    }

    @Test("JSONRPCMessage encoding preserves variant")
    func testJSONRPCMessageEncodingPreservesVariant() throws {
        let request = JSONRPCMessage.request(JSONRPCRequest(id: .int(1), method: "test"))
        let response = JSONRPCMessage.response(JSONRPCResponse(id: .int(2), result: .null))
        let error = JSONRPCMessage.error(JSONRPCError(
            id: .int(3),
            error: JSONRPCErrorObject(code: -32600, message: "Error")
        ))
        let notification = JSONRPCMessage.notification(JSONRPCNotification(method: "notify"))

        let encodedRequest = try JSONEncoder().encode(request)
        let encodedResponse = try JSONEncoder().encode(response)
        let encodedError = try JSONEncoder().encode(error)
        let encodedNotification = try JSONEncoder().encode(notification)

        let decodedRequest = try JSONDecoder().decode(JSONRPCMessage.self, from: encodedRequest)
        let decodedResponse = try JSONDecoder().decode(JSONRPCMessage.self, from: encodedResponse)
        let decodedError = try JSONDecoder().decode(JSONRPCMessage.self, from: encodedError)
        let decodedNotification = try JSONDecoder().decode(JSONRPCMessage.self, from: encodedNotification)

        if case .request = decodedRequest {} else { Issue.record("Expected request") }
        if case .response = decodedResponse {} else { Issue.record("Expected response") }
        if case .error = decodedError {} else { Issue.record("Expected error") }
        if case .notification = decodedNotification {} else { Issue.record("Expected notification") }
    }

    @Test("JSONRPCMessage rejects invalid jsonrpc version")
    func testJSONRPCMessageRejectsInvalidVersion() throws {
        let json = """
        {
            "jsonrpc": "1.0",
            "id": 1,
            "method": "test"
        }
        """.data(using: .utf8)!

        #expect(throws: Error.self) {
            try JSONDecoder().decode(JSONRPCMessage.self, from: json)
        }
    }

    @Test("JSONRPCMessage rejects message without required fields")
    func testJSONRPCMessageRejectsInvalidMessage() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 1
        }
        """.data(using: .utf8)!

        #expect(throws: Error.self) {
            try JSONDecoder().decode(JSONRPCMessage.self, from: json)
        }
    }

    @Test("JSONRPCMessage distinguishes request from notification")
    func testJSONRPCMessageDistinguishesRequestFromNotification() throws {
        let requestJSON = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "test"
        }
        """.data(using: .utf8)!

        let notificationJSON = """
        {
            "jsonrpc": "2.0",
            "method": "test"
        }
        """.data(using: .utf8)!

        let decodedRequest = try JSONDecoder().decode(JSONRPCMessage.self, from: requestJSON)
        let decodedNotification = try JSONDecoder().decode(JSONRPCMessage.self, from: notificationJSON)

        // Request has ID, notification doesn't
        if case .request(let req) = decodedRequest {
            #expect(req.id == .int(1))
        } else {
            Issue.record("Expected request with ID")
        }

        if case .notification = decodedNotification {
            // Success - no ID present
        } else {
            Issue.record("Expected notification without ID")
        }
    }

    @Test("JSONRPCMessage handles complex result objects")
    func testJSONRPCMessageComplexResult() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "complex-1",
            "result": {
                "tools": [
                    {"name": "tool1", "description": "First tool"},
                    {"name": "tool2", "description": "Second tool"}
                ],
                "nextCursor": "abc123",
                "_meta": {"page": 1}
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JSONRPCMessage.self, from: json)

        if case .response(let response) = decoded {
            #expect(response.id == .string("complex-1"))
            if case .object(let obj) = response.result {
                #expect(obj["tools"] != nil)
                #expect(obj["nextCursor"] == .string("abc123"))
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected response variant")
        }
    }
}
