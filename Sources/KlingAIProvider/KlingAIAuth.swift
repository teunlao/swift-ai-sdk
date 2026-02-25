import Foundation
import CryptoKit
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/klingai/src/klingai-auth.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

/// Generate a JWT authentication token for KlingAI API access (HS256).
///
/// Upstream uses the Web Crypto API and is async; the Swift port exposes the same
/// async surface but uses CryptoKit.
public func generateKlingAIAuthToken(
    accessKey: String? = nil,
    secretKey: String? = nil
) async throws -> String {
    let ak = try loadSetting(
        settingValue: accessKey,
        environmentVariableName: "KLINGAI_ACCESS_KEY",
        settingName: "accessKey",
        description: "KlingAI access key"
    )

    let sk = try loadSetting(
        settingValue: secretKey,
        environmentVariableName: "KLINGAI_SECRET_KEY",
        settingName: "secretKey",
        description: "KlingAI secret key"
    )

    let now = Int(Date().timeIntervalSince1970)

    // Header and payload shapes match upstream.
    let headerData = try JSONSerialization.data(
        withJSONObject: ["alg": "HS256", "typ": "JWT"],
        options: [.sortedKeys]
    )

    let payloadData = try JSONSerialization.data(
        withJSONObject: [
            "iss": ak,
            "exp": now + 1800, // 30 minutes
            "nbf": now - 5, // 5 seconds before
        ],
        options: [.sortedKeys]
    )

    let headerPart = base64urlEncode(headerData)
    let payloadPart = base64urlEncode(payloadData)
    let signingInput = "\(headerPart).\(payloadPart)"

    let key = SymmetricKey(data: Data(sk.utf8))
    let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
    let signaturePart = base64urlEncode(Data(signature))

    return "\(signingInput).\(signaturePart)"
}

private func base64urlEncode(_ data: Data) -> String {
    data
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
