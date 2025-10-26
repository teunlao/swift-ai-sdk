import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-config.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct GatewayConfig: Sendable {
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
}

struct GatewayLanguageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}

struct GatewayEmbeddingModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}
