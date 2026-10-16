import Foundation
import CryptoKit
import AISDKProvider

/**
 Secret for HMAC-signing tool approval requests.

 Port of the `experimental_toolApprovalSecret` option (`string | Uint8Array`):
 when set, each approval request is signed at issuance and the signature is
 verified before an approved call from client-supplied history executes.
 */
public struct ToolApprovalSecret: Sendable, ExpressibleByStringLiteral {
    let key: SymmetricKey

    public init(_ secret: String) {
        key = SymmetricKey(data: Data(secret.utf8))
    }

    public init(_ secret: Data) {
        key = SymmetricKey(data: secret)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }
}

/**
 Signs a tool approval request.

 Port of `signToolApproval` from `@ai-sdk/ai/src/generate-text/tool-approval-signature.ts`:
 HMAC-SHA256 over the JSON array `["ai-sdk-tool-approval-v1", approvalId,
 toolCallId, toolName, inputDigest]`, base64url-encoded.
 */
func signToolApproval(
    secret: ToolApprovalSecret,
    approvalId: String,
    toolCallId: String,
    toolName: String,
    input: JSONValue
) throws -> String {
    let payload = try approvalPayload(approvalId: approvalId, toolCallId: toolCallId, toolName: toolName, input: input)
    let signature = HMAC<SHA256>.authenticationCode(for: payload, using: secret.key)
    return base64URLEncoded(Data(signature))
}

/**
 Verifies a tool approval signature.

 Port of `verifyToolApprovalSignature`. Upstream also accepts the pre-JSON
 newline-joined payload for approvals signed by older releases; this port never
 issued that format, so it is not accepted.
 */
func verifyToolApprovalSignature(
    secret: ToolApprovalSecret,
    signature: String,
    approvalId: String,
    toolCallId: String,
    toolName: String,
    input: JSONValue
) throws -> Bool {
    guard let signatureBytes = base64URLDecoded(signature) else { return false }
    let payload = try approvalPayload(approvalId: approvalId, toolCallId: toolCallId, toolName: toolName, input: input)
    return HMAC<SHA256>.isValidAuthenticationCode(signatureBytes, authenticating: payload, using: secret.key)
}

/// Signs when a secret is configured.
func maybeSignApproval(
    secret: ToolApprovalSecret?,
    approvalId: String,
    toolCall: TypedToolCall
) throws -> String? {
    guard let secret else { return nil }
    return try signToolApproval(
        secret: secret,
        approvalId: approvalId,
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: toolCall.input
    )
}

// The JSON array keeps field boundaries unambiguous; the version string separates domains.
private func approvalPayload(approvalId: String, toolCallId: String, toolName: String, input: JSONValue) throws -> Data {
    let fields: JSONValue = .array([
        .string("ai-sdk-tool-approval-v1"),
        .string(approvalId),
        .string(toolCallId),
        .string(toolName),
        .string(try hashCanonical(input)),
    ])
    return Data(try canonicalJSON(fields).utf8)
}

private func base64URLEncoded(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func base64URLDecoded(_ string: String) -> Data? {
    var base64 = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
        base64 += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: base64)
}
