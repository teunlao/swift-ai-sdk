import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/vercel-environment.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

enum GatewayEnvironmentError: Error, Sendable {
    case oidcTokenUnavailable
}

func getVercelOidcToken() async throws -> String {
    if let token = ProcessInfo.processInfo.environment["VERCEL_OIDC_TOKEN"], !token.isEmpty {
        return token
    }
    throw GatewayEnvironmentError.oidcTokenUnavailable
}

func getVercelRequestId() async -> String? {
    ProcessInfo.processInfo.environment["VERCEL_REQUEST_ID"]
}
