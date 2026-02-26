import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-config.ts
// Upstream commit: 73d5c5920
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

struct GatewayImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}

struct GatewayVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}
