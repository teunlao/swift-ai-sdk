import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/vercel-environment.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

enum GatewayEnvironmentError: Error, Sendable {
    case oidcTokenUnavailable
}

/// A best-effort Swift adaptation of Vercel's request context used by the
/// upstream JS implementation (`@vercel/request-context`).
///
/// When running inside Vercel, the Node runtime can read request headers via
/// `@vercel/oidc` context. In Swift, we expose a `TaskLocal` hook so host apps
/// can propagate request headers (for o11y and request-id correlation).
public enum GatewayVercelRequestContext {
    @TaskLocal public static var headers: [String: String]?
}

func getVercelOidcToken() async throws -> String {
    if let token = ProcessInfo.processInfo.environment["VERCEL_OIDC_TOKEN"], !token.isEmpty {
        return token
    }
    throw GatewayEnvironmentError.oidcTokenUnavailable
}

func getVercelRequestId() async -> String? {
    if let headers = GatewayVercelRequestContext.headers {
        for (key, value) in headers where key.lowercased() == "x-vercel-id" {
            return value
        }
    }

    // Fallback for non-context environments (useful for CLI/tests).
    if let value = ProcessInfo.processInfo.environment["VERCEL_REQUEST_ID"], !value.isEmpty {
        return value
    }

    return nil
}
