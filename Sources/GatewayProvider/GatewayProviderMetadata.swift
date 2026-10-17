import Foundation
import AISDKProvider

public struct GatewayAsyncJobMetadata: Sendable, Codable, Equatable {
    public let jobId: String
    public let status: String
    /// Sensitive start-response metadata used to verify webhook deliveries.
    public let webhookSigningSecret: String?
    public let additionalMetadata: [String: JSONValue]

    public init(
        jobId: String,
        status: String,
        webhookSigningSecret: String? = nil,
        additionalMetadata: [String: JSONValue] = [:]
    ) {
        self.jobId = jobId
        self.status = status
        self.webhookSigningSecret = webhookSigningSecret
        self.additionalMetadata = additionalMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: GatewayCodingKey.self)
        jobId = try container.decode(String.self, forKey: .init("jobId"))
        status = try container.decode(String.self, forKey: .init("status"))
        webhookSigningSecret = try container.decodeIfPresent(String.self, forKey: .init("webhookSigningSecret"))
        additionalMetadata = try container.allKeys.reduce(into: [:]) { values, key in
            if !["jobId", "status", "webhookSigningSecret"].contains(key.stringValue) {
                values[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: GatewayCodingKey.self)
        for (key, value) in additionalMetadata where !["jobId", "status", "webhookSigningSecret"].contains(key) {
            try container.encode(value, forKey: .init(key))
        }
        try container.encode(jobId, forKey: .init("jobId"))
        try container.encode(status, forKey: .init("status"))
        try container.encodeIfPresent(webhookSigningSecret, forKey: .init("webhookSigningSecret"))
    }
}

public struct GatewayProviderMetadata: Sendable, Codable, Equatable {
    public let asyncJob: GatewayAsyncJobMetadata?
    public let additionalMetadata: [String: JSONValue]

    public init(asyncJob: GatewayAsyncJobMetadata? = nil, additionalMetadata: [String: JSONValue] = [:]) {
        self.asyncJob = asyncJob
        self.additionalMetadata = additionalMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: GatewayCodingKey.self)
        asyncJob = try container.decodeIfPresent(GatewayAsyncJobMetadata.self, forKey: .init("asyncJob"))
        additionalMetadata = try container.allKeys.reduce(into: [:]) { values, key in
            if key.stringValue != "asyncJob" {
                values[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: GatewayCodingKey.self)
        for (key, value) in additionalMetadata where key != "asyncJob" {
            try container.encode(value, forKey: .init(key))
        }
        try container.encodeIfPresent(asyncJob, forKey: .init("asyncJob"))
    }
}
