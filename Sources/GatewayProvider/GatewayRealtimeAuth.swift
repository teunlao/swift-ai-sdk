import Foundation
import AISDKProvider

public let GATEWAY_REALTIME_SUBPROTOCOL = "ai-gateway-realtime.v1"
public let GATEWAY_TRANSCRIPTION_SUBPROTOCOL = "ai-gateway-transcription.v1"
public let GATEWAY_AUTH_SUBPROTOCOL_PREFIX = "ai-gateway-auth."
public let GATEWAY_TEAM_SUBPROTOCOL_PREFIX = "ai-gateway-team."

public func getGatewayRealtimeProtocols(_ token: String, teamIdOrSlug: String? = nil) -> [String] {
    gatewayProtocols(marker: GATEWAY_REALTIME_SUBPROTOCOL, token: token, teamIdOrSlug: teamIdOrSlug)
}

public func getGatewayTranscriptionProtocols(_ token: String, teamIdOrSlug: String? = nil) -> [String] {
    gatewayProtocols(marker: GATEWAY_TRANSCRIPTION_SUBPROTOCOL, token: token, teamIdOrSlug: teamIdOrSlug)
}

public func getGatewayRealtimeAuthToken(_ secWebSocketProtocol: String?) -> String? {
    gatewayProtocolValue(secWebSocketProtocol, prefix: GATEWAY_AUTH_SUBPROTOCOL_PREFIX)
}

public func getGatewayRealtimeTeamIdOrSlug(_ secWebSocketProtocol: String?) -> String? {
    guard let value = gatewayProtocolValue(secWebSocketProtocol, prefix: GATEWAY_TEAM_SUBPROTOCOL_PREFIX) else { return nil }
    var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let bytes = Data(base64Encoded: base64) else { return nil }
    let result = String(decoding: bytes, as: UTF8.self)
    return result.isEmpty ? nil : result
}

private func gatewayProtocols(marker: String, token: String, teamIdOrSlug: String?) -> [String] {
    var result = [marker, GATEWAY_AUTH_SUBPROTOCOL_PREFIX + token]
    if let teamIdOrSlug, !teamIdOrSlug.isEmpty {
        let value = Data(teamIdOrSlug.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        result.append(GATEWAY_TEAM_SUBPROTOCOL_PREFIX + value)
    }
    return result
}

private func gatewayProtocolValue(_ header: String?, prefix: String) -> String? {
    guard let match = header?.split(separator: ",", omittingEmptySubsequences: false)
        .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { $0.hasPrefix(prefix) }) else { return nil }
    let value = String(match.dropFirst(prefix.count))
    return value.isEmpty ? nil : value
}

public func toGatewayTranscriptionUrl(_ baseURL: String, modelId: String) throws -> String {
    try gatewayWebSocketURL(baseURL, modelId: modelId, endpoint: "transcription-model")
}

func gatewayWebSocketURL(_ baseURL: String, modelId: String, endpoint: String) throws -> String {
    guard var components = URLComponents(string: "\(baseURL)/\(endpoint)"), components.host != nil else {
        throw InvalidArgumentError(argument: "baseURL", message: "Invalid Gateway URL: \(baseURL)")
    }
    if components.scheme == "https" { components.scheme = "wss" }
    else if components.scheme == "http" { components.scheme = "ws" }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._")
    let encoded = modelId.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: "%20", with: "+") ?? ""
    components.percentEncodedQuery = "ai-model-id=\(encoded)"
    guard let value = components.string else {
        throw InvalidArgumentError(argument: "baseURL", message: "Invalid Gateway URL: \(baseURL)")
    }
    return value
}
