import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/parse-auth-method.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public enum GatewayAuthMethod: String, Sendable {
    case apiKey = "api-key"
    case oidc = "oidc"
}

public let GATEWAY_AUTH_METHOD_HEADER = "ai-gateway-auth-method"

func parseAuthMethod(from headers: [String: String]) -> GatewayAuthMethod? {
    guard let value = headers[GATEWAY_AUTH_METHOD_HEADER]?.lowercased() else {
        return nil
    }
    return GatewayAuthMethod(rawValue: value)
}
