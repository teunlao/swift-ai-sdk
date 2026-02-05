import Foundation
import AISDKProvider

/**
 OAuth types for MCP.

 Port of `packages/mcp/src/tool/oauth-types.ts`.
 Upstream commit: f3a72bc2a
 */

// MARK: - SafeURL

public struct SafeURL: Codable, Sendable, Hashable {
    public let url: URL

    public init(_ url: URL) throws {
        try SafeURL.validate(url)
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        guard let url = URL(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "URL must be parseable"
            )
        }

        try SafeURL.validate(url)
        self.url = url
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url.absoluteString)
    }

    private static func validate(_ url: URL) throws {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme.isEmpty {
            throw SafeURLValidationError.invalidURL(url: url.absoluteString)
        }

        if scheme == "javascript" || scheme == "data" || scheme == "vbscript" {
            throw SafeURLValidationError.disallowedScheme(url: url.absoluteString, scheme: scheme)
        }
    }
}

public enum SafeURLValidationError: Error, LocalizedError, Sendable {
    case invalidURL(url: String)
    case disallowedScheme(url: String, scheme: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "URL must be parseable: \(url)"
        case .disallowedScheme(let url, let scheme):
            return "URL cannot use javascript:, data:, or vbscript: scheme (got \(scheme)) for \(url)"
        }
    }
}

// MARK: - Token Response

/// OAuth 2.1 token response.
public struct OAuthTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let idToken: String?
    public let tokenType: String
    public let expiresIn: Double?
    public let scope: String?
    public let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case refreshToken = "refresh_token"
    }

    public init(
        accessToken: String,
        idToken: String? = nil,
        tokenType: String,
        expiresIn: Double? = nil,
        scope: String? = nil,
        refreshToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.refreshToken = refreshToken
    }
}

// MARK: - Protected Resource Metadata (RFC 9728)

public struct OAuthProtectedResourceMetadata: Codable, Sendable, Equatable {
    public let resource: URL
    public let authorizationServers: [SafeURL]?
    public let jwksUri: URL?
    public let scopesSupported: [String]?
    public let bearerMethodsSupported: [String]?
    public let resourceSigningAlgValuesSupported: [String]?
    public let resourceName: String?
    public let resourceDocumentation: String?
    public let resourcePolicyUri: URL?
    public let resourceTosUri: URL?
    public let tlsClientCertificateBoundAccessTokens: Bool?
    public let authorizationDetailsTypesSupported: [String]?
    public let dpopSigningAlgValuesSupported: [String]?
    public let dpopBoundAccessTokensRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case jwksUri = "jwks_uri"
        case scopesSupported = "scopes_supported"
        case bearerMethodsSupported = "bearer_methods_supported"
        case resourceSigningAlgValuesSupported = "resource_signing_alg_values_supported"
        case resourceName = "resource_name"
        case resourceDocumentation = "resource_documentation"
        case resourcePolicyUri = "resource_policy_uri"
        case resourceTosUri = "resource_tos_uri"
        case tlsClientCertificateBoundAccessTokens = "tls_client_certificate_bound_access_tokens"
        case authorizationDetailsTypesSupported = "authorization_details_types_supported"
        case dpopSigningAlgValuesSupported = "dpop_signing_alg_values_supported"
        case dpopBoundAccessTokensRequired = "dpop_bound_access_tokens_required"
    }
}

// MARK: - Authorization Server Metadata

/// Authorization server metadata (OAuth or OIDC discovery).
///
/// Swift simplification: represents the shared fields used by MCP OAuth flows.
public struct AuthorizationServerMetadata: Codable, Sendable, Equatable {
    public let issuer: String
    public let authorizationEndpoint: SafeURL
    public let tokenEndpoint: SafeURL
    public let registrationEndpoint: SafeURL?
    public let scopesSupported: [String]?
    public let responseTypesSupported: [String]
    public let grantTypesSupported: [String]?
    public let codeChallengeMethodsSupported: [String]?
    public let tokenEndpointAuthMethodsSupported: [String]?
    public let tokenEndpointAuthSigningAlgValuesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case tokenEndpointAuthSigningAlgValuesSupported = "token_endpoint_auth_signing_alg_values_supported"
    }
}

// MARK: - Client Registration Types

public struct OAuthClientInformation: Codable, Sendable, Equatable {
    public let clientId: String
    public let clientSecret: String?
    public let clientIdIssuedAt: Double?
    public let clientSecretExpiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case clientIdIssuedAt = "client_id_issued_at"
        case clientSecretExpiresAt = "client_secret_expires_at"
    }
}

public struct OAuthClientMetadata: Codable, Sendable, Equatable {
    public let redirectUris: [SafeURL]
    public let tokenEndpointAuthMethod: String?
    public let grantTypes: [String]?
    public let responseTypes: [String]?
    public let clientName: String?
    public let clientUri: SafeURL?
    public let logoUri: SafeURL?
    public let scope: String?
    public let contacts: [String]?
    public let tosUri: SafeURL?
    public let policyUri: String?
    public let jwksUri: SafeURL?
    public let jwks: JSONValue?
    public let softwareId: String?
    public let softwareVersion: String?
    public let softwareStatement: String?

    enum CodingKeys: String, CodingKey {
        case redirectUris = "redirect_uris"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case grantTypes = "grant_types"
        case responseTypes = "response_types"
        case clientName = "client_name"
        case clientUri = "client_uri"
        case logoUri = "logo_uri"
        case scope
        case contacts
        case tosUri = "tos_uri"
        case policyUri = "policy_uri"
        case jwksUri = "jwks_uri"
        case jwks
        case softwareId = "software_id"
        case softwareVersion = "software_version"
        case softwareStatement = "software_statement"
    }
}

public struct OAuthClientInformationFull: Codable, Sendable, Equatable {
    public let clientId: String
    public let clientSecret: String?
    public let clientIdIssuedAt: Double?
    public let clientSecretExpiresAt: Double?
    public let redirectUris: [SafeURL]
    public let tokenEndpointAuthMethod: String?
    public let grantTypes: [String]?
    public let responseTypes: [String]?
    public let clientName: String?
    public let clientUri: SafeURL?
    public let logoUri: SafeURL?
    public let scope: String?
    public let contacts: [String]?
    public let tosUri: SafeURL?
    public let policyUri: String?
    public let jwksUri: SafeURL?
    public let jwks: JSONValue?
    public let softwareId: String?
    public let softwareVersion: String?
    public let softwareStatement: String?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case clientIdIssuedAt = "client_id_issued_at"
        case clientSecretExpiresAt = "client_secret_expires_at"
        case redirectUris = "redirect_uris"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case grantTypes = "grant_types"
        case responseTypes = "response_types"
        case clientName = "client_name"
        case clientUri = "client_uri"
        case logoUri = "logo_uri"
        case scope
        case contacts
        case tosUri = "tos_uri"
        case policyUri = "policy_uri"
        case jwksUri = "jwks_uri"
        case jwks
        case softwareId = "software_id"
        case softwareVersion = "software_version"
        case softwareStatement = "software_statement"
    }
}

public struct OAuthErrorResponse: Codable, Sendable, Equatable {
    public let error: String
    public let errorDescription: String?
    public let errorUri: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case errorUri = "error_uri"
    }
}
