import Foundation
import CryptoKit
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/klingai/src/klingai-auth.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

func resolveKlingAIAuthToken(apiKey: String?, accessKey: String?, secretKey: String?) async throws -> String {
    if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty { return key }
    if accessKey != nil && secretKey != nil { return try await generateKlingAIAuthToken(accessKey: accessKey, secretKey: secretKey) }
    let environmentKey = loadOptionalSetting(settingValue: nil, environmentVariableName: "KLINGAI_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let environmentKey, !environmentKey.isEmpty { return environmentKey }
    let access = loadOptionalSetting(settingValue: accessKey, environmentVariableName: "KLINGAI_ACCESS_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let secret = loadOptionalSetting(settingValue: secretKey, environmentVariableName: "KLINGAI_SECRET_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !(access?.isEmpty ?? true) || !(secret?.isEmpty ?? true) else {
        throw LoadAPIKeyError(message: "KlingAI API key is missing. Pass it using the 'apiKey' parameter or the KLINGAI_API_KEY environment variable. Alternatively, pass the legacy 'accessKey' and 'secretKey' parameters or the KLINGAI_ACCESS_KEY and KLINGAI_SECRET_KEY environment variables.")
    }
    return try await generateKlingAIAuthToken(accessKey: accessKey, secretKey: secretKey)
}

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
