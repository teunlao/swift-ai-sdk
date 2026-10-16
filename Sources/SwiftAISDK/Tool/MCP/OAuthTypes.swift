import Foundation
import AISDKProvider

/**
 OAuth types for MCP.

 Port of `packages/mcp/src/tool/oauth-types.ts`.
 Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
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
        if !isAbsoluteURL(url) {
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
    public var refreshToken: String?
    public var issuer: SafeURL? = nil
    public var authorizationServer: SafeURL? = nil
    public var tokenEndpoint: SafeURL? = nil

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case refreshToken = "refresh_token"
        case issuer
        case authorizationServer = "authorization_server"
        case tokenEndpoint = "token_endpoint"
    }

    public init(
        accessToken: String,
        idToken: String? = nil,
        tokenType: String,
        expiresIn: Double? = nil,
        scope: String? = nil,
        refreshToken: String? = nil,
        issuer: SafeURL? = nil,
        authorizationServer: SafeURL? = nil,
        tokenEndpoint: SafeURL? = nil
    ) {
        self.accessToken = accessToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.refreshToken = refreshToken
        self.issuer = issuer
        self.authorizationServer = authorizationServer
        self.tokenEndpoint = tokenEndpoint
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
    public var additionalProperties: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
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
/// OAuth and OIDC metadata share one Swift representation.
public struct AuthorizationServerMetadata: Codable, Sendable, Equatable {
    public init(
        issuer: String,
        authorizationEndpoint: SafeURL,
        tokenEndpoint: SafeURL,
        registrationEndpoint: SafeURL? = nil,
        authorizationResponseIssParameterSupported: Bool? = nil,
        clientIdMetadataDocumentSupported: Bool? = nil,
        scopesSupported: [String]? = nil,
        responseTypesSupported: [String],
        grantTypesSupported: [String]? = nil,
        codeChallengeMethodsSupported: [String]? = nil,
        tokenEndpointAuthMethodsSupported: [String]? = nil,
        tokenEndpointAuthSigningAlgValuesSupported: [String]? = nil,
        userinfoEndpoint: SafeURL? = nil,
        jwksUri: SafeURL? = nil,
        subjectTypesSupported: [String]? = nil,
        idTokenSigningAlgValuesSupported: [String]? = nil,
        claimsSupported: [String]? = nil,
        additionalProperties: [String: JSONValue] = [:]
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.authorizationResponseIssParameterSupported = authorizationResponseIssParameterSupported
        self.clientIdMetadataDocumentSupported = clientIdMetadataDocumentSupported
        self.scopesSupported = scopesSupported
        self.responseTypesSupported = responseTypesSupported
        self.grantTypesSupported = grantTypesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.tokenEndpointAuthMethodsSupported = tokenEndpointAuthMethodsSupported
        self.tokenEndpointAuthSigningAlgValuesSupported = tokenEndpointAuthSigningAlgValuesSupported
        self.userinfoEndpoint = userinfoEndpoint
        self.jwksUri = jwksUri
        self.subjectTypesSupported = subjectTypesSupported
        self.idTokenSigningAlgValuesSupported = idTokenSigningAlgValuesSupported
        self.claimsSupported = claimsSupported
        self.additionalProperties = additionalProperties
    }

    public let issuer: String
    public let authorizationEndpoint: SafeURL
    public let tokenEndpoint: SafeURL
    public let registrationEndpoint: SafeURL?
    public var authorizationResponseIssParameterSupported: Bool? = nil
    public var clientIdMetadataDocumentSupported: Bool? = nil
    public let scopesSupported: [String]?
    public let responseTypesSupported: [String]
    public let grantTypesSupported: [String]?
    public let codeChallengeMethodsSupported: [String]?
    public let tokenEndpointAuthMethodsSupported: [String]?
    public let tokenEndpointAuthSigningAlgValuesSupported: [String]?
    public let userinfoEndpoint: SafeURL?
    public let jwksUri: SafeURL?
    public let subjectTypesSupported: [String]?
    public let idTokenSigningAlgValuesSupported: [String]?
    public let claimsSupported: [String]?
    public var additionalProperties: [String: JSONValue]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case authorizationResponseIssParameterSupported = "authorization_response_iss_parameter_supported"
        case clientIdMetadataDocumentSupported = "client_id_metadata_document_supported"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case tokenEndpointAuthSigningAlgValuesSupported = "token_endpoint_auth_signing_alg_values_supported"
        case userinfoEndpoint = "userinfo_endpoint"
        case jwksUri = "jwks_uri"
        case subjectTypesSupported = "subject_types_supported"
        case idTokenSigningAlgValuesSupported = "id_token_signing_alg_values_supported"
        case claimsSupported = "claims_supported"
    }
}

// MARK: - Client Registration Types

public enum OAuthApplicationType: String, Codable, Sendable {
    case native
    case web
}

public struct OAuthClientInformation: Codable, Sendable, Equatable {
    public let registrationMetadata: OAuthClientMetadata?

    public init(_ registration: OAuthClientInformationFull) {
        self.init(
            clientId: registration.clientId, clientSecret: registration.clientSecret,
            clientIdIssuedAt: registration.clientIdIssuedAt, clientSecretExpiresAt: registration.clientSecretExpiresAt,
            issuer: registration.issuer, authorizationServer: registration.authorizationServer, tokenEndpoint: registration.tokenEndpoint,
            registrationMetadata: OAuthClientMetadata(
                redirectUris: registration.redirectUris, applicationType: registration.applicationType,
                tokenEndpointAuthMethod: registration.tokenEndpointAuthMethod, grantTypes: registration.grantTypes,
                responseTypes: registration.responseTypes, clientName: registration.clientName,
                clientUri: registration.clientUri, logoUri: registration.logoUri, scope: registration.scope,
                contacts: registration.contacts, tosUri: registration.tosUri, policyUri: registration.policyUri,
                jwksUri: registration.jwksUri, jwks: registration.jwks, softwareId: registration.softwareId,
                softwareVersion: registration.softwareVersion, softwareStatement: registration.softwareStatement
            )
        )
    }

    public init(
        clientId: String,
        clientSecret: String? = nil,
        clientIdIssuedAt: Double? = nil,
        clientSecretExpiresAt: Double? = nil,
        issuer: SafeURL? = nil,
        authorizationServer: SafeURL? = nil,
        tokenEndpoint: SafeURL? = nil,
        registrationMetadata: OAuthClientMetadata? = nil
    ) {
        self.registrationMetadata = registrationMetadata
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.clientIdIssuedAt = clientIdIssuedAt
        self.clientSecretExpiresAt = clientSecretExpiresAt
        self.issuer = issuer
        self.authorizationServer = authorizationServer
        self.tokenEndpoint = tokenEndpoint
    }

    public let clientId: String
    public let clientSecret: String?
    public let clientIdIssuedAt: Double?
    public let clientSecretExpiresAt: Double?
    public var issuer: SafeURL? = nil
    public var authorizationServer: SafeURL? = nil
    public var tokenEndpoint: SafeURL? = nil

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case clientIdIssuedAt = "client_id_issued_at"
        case clientSecretExpiresAt = "client_secret_expires_at"
        case issuer
        case authorizationServer = "authorization_server"
        case tokenEndpoint = "token_endpoint"
    }
}

public struct OAuthClientMetadata: Codable, Sendable, Equatable {
    public init(
        redirectUris: [SafeURL],
        applicationType: OAuthApplicationType? = nil,
        tokenEndpointAuthMethod: String? = nil,
        grantTypes: [String]? = nil,
        responseTypes: [String]? = nil,
        clientName: String? = nil,
        clientUri: SafeURL? = nil,
        logoUri: SafeURL? = nil,
        scope: String? = nil,
        contacts: [String]? = nil,
        tosUri: SafeURL? = nil,
        policyUri: String? = nil,
        jwksUri: SafeURL? = nil,
        jwks: JSONValue? = nil,
        softwareId: String? = nil,
        softwareVersion: String? = nil,
        softwareStatement: String? = nil
    ) {
        self.redirectUris = redirectUris
        self.applicationType = applicationType
        self.tokenEndpointAuthMethod = tokenEndpointAuthMethod
        self.grantTypes = grantTypes
        self.responseTypes = responseTypes
        self.clientName = clientName
        self.clientUri = clientUri
        self.logoUri = logoUri
        self.scope = scope
        self.contacts = contacts
        self.tosUri = tosUri
        self.policyUri = policyUri
        self.jwksUri = jwksUri
        self.jwks = jwks
        self.softwareId = softwareId
        self.softwareVersion = softwareVersion
        self.softwareStatement = softwareStatement
    }

    public let redirectUris: [SafeURL]
    public var applicationType: OAuthApplicationType? = nil
    public let tokenEndpointAuthMethod: String?
    public let grantTypes: [String]?
    public let responseTypes: [String]?
    public let clientName: String?
    public let clientUri: SafeURL?
    public let logoUri: SafeURL?
    public var scope: String?
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
        case applicationType = "application_type"
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
    public var issuer: SafeURL? = nil
    public var authorizationServer: SafeURL? = nil
    public var tokenEndpoint: SafeURL? = nil
    public let redirectUris: [SafeURL]
    public var applicationType: OAuthApplicationType? = nil
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
        case issuer
        case authorizationServer = "authorization_server"
        case tokenEndpoint = "token_endpoint"
        case redirectUris = "redirect_uris"
        case applicationType = "application_type"
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

private func isAbsoluteURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme, !scheme.isEmpty else { return false }
    if ["http", "https", "ftp", "ws", "wss"].contains(scheme.lowercased()) {
        guard let host = url.host, !host.isEmpty else { return false }
        if let port = url.port, !(0...65535).contains(port) { return false }
    }
    return true
}

private struct OAuthCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { Int(stringValue) }

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { self.init(String(intValue)) }
}

private extension KeyedDecodingContainer {
    // OAuth optional fields may be omitted; JSON null is not an omitted value.
    func decodeOptional<Value: Decodable>(_ type: Value.Type, forKey key: Key) throws -> Value? {
        contains(key) ? try decode(type, forKey: key) : nil
    }

    func decodeAbsoluteURL(forKey key: Key) throws -> URL {
        let raw = try decode(String.self, forKey: key)
        guard let url = URL(string: raw), isAbsoluteURL(url) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected an absolute URL")
        }
        return url
    }

    func decodeOptionalURL(forKey key: Key) throws -> URL? {
        contains(key) ? try decodeAbsoluteURL(forKey: key) : nil
    }
}

private func decodeAdditionalProperties<Keys: CodingKey & CaseIterable>(
    from decoder: Decoder,
    excluding: Keys.Type
) throws -> [String: JSONValue] {
    let container = try decoder.container(keyedBy: OAuthCodingKey.self)
    let known = Set(Keys.allCases.map(\.stringValue))
    var properties: [String: JSONValue] = [:]
    for key in container.allKeys where !known.contains(key.stringValue) {
        properties[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
    }
    return properties
}

private func encodeAdditionalProperties<Keys: CodingKey & CaseIterable>(
    _ properties: [String: JSONValue],
    to encoder: Encoder,
    excluding: Keys.Type
) throws {
    var container = encoder.container(keyedBy: OAuthCodingKey.self)
    let known = Set(Keys.allCases.map(\.stringValue))
    for (key, value) in properties where !known.contains(key) {
        try container.encode(value, forKey: OAuthCodingKey(key))
    }
}

extension OAuthTokens {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            accessToken: try container.decode(String.self, forKey: .accessToken),
            idToken: try container.decodeOptional(String.self, forKey: .idToken),
            tokenType: try container.decode(String.self, forKey: .tokenType),
            expiresIn: try container.decodeOptional(Double.self, forKey: .expiresIn),
            scope: try container.decodeOptional(String.self, forKey: .scope),
            refreshToken: try container.decodeOptional(String.self, forKey: .refreshToken),
            issuer: try container.decodeOptional(SafeURL.self, forKey: .issuer),
            authorizationServer: try container.decodeOptional(SafeURL.self, forKey: .authorizationServer),
            tokenEndpoint: try container.decodeOptional(SafeURL.self, forKey: .tokenEndpoint)
        )
    }
}

extension OAuthProtectedResourceMetadata {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resource = try container.decodeAbsoluteURL(forKey: .resource)
        authorizationServers = try container.decodeOptional([SafeURL].self, forKey: .authorizationServers)
        jwksUri = try container.decodeOptionalURL(forKey: .jwksUri)
        scopesSupported = try container.decodeOptional([String].self, forKey: .scopesSupported)
        bearerMethodsSupported = try container.decodeOptional([String].self, forKey: .bearerMethodsSupported)
        resourceSigningAlgValuesSupported = try container.decodeOptional([String].self, forKey: .resourceSigningAlgValuesSupported)
        resourceName = try container.decodeOptional(String.self, forKey: .resourceName)
        resourceDocumentation = try container.decodeOptional(String.self, forKey: .resourceDocumentation)
        resourcePolicyUri = try container.decodeOptionalURL(forKey: .resourcePolicyUri)
        resourceTosUri = try container.decodeOptionalURL(forKey: .resourceTosUri)
        tlsClientCertificateBoundAccessTokens = try container.decodeOptional(Bool.self, forKey: .tlsClientCertificateBoundAccessTokens)
        authorizationDetailsTypesSupported = try container.decodeOptional([String].self, forKey: .authorizationDetailsTypesSupported)
        dpopSigningAlgValuesSupported = try container.decodeOptional([String].self, forKey: .dpopSigningAlgValuesSupported)
        dpopBoundAccessTokensRequired = try container.decodeOptional(Bool.self, forKey: .dpopBoundAccessTokensRequired)
        additionalProperties = try decodeAdditionalProperties(from: decoder, excluding: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeAdditionalProperties(additionalProperties, to: encoder, excluding: CodingKeys.self)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resource, forKey: .resource)
        try container.encodeIfPresent(authorizationServers, forKey: .authorizationServers)
        try container.encodeIfPresent(jwksUri, forKey: .jwksUri)
        try container.encodeIfPresent(scopesSupported, forKey: .scopesSupported)
        try container.encodeIfPresent(bearerMethodsSupported, forKey: .bearerMethodsSupported)
        try container.encodeIfPresent(resourceSigningAlgValuesSupported, forKey: .resourceSigningAlgValuesSupported)
        try container.encodeIfPresent(resourceName, forKey: .resourceName)
        try container.encodeIfPresent(resourceDocumentation, forKey: .resourceDocumentation)
        try container.encodeIfPresent(resourcePolicyUri, forKey: .resourcePolicyUri)
        try container.encodeIfPresent(resourceTosUri, forKey: .resourceTosUri)
        try container.encodeIfPresent(tlsClientCertificateBoundAccessTokens, forKey: .tlsClientCertificateBoundAccessTokens)
        try container.encodeIfPresent(authorizationDetailsTypesSupported, forKey: .authorizationDetailsTypesSupported)
        try container.encodeIfPresent(dpopSigningAlgValuesSupported, forKey: .dpopSigningAlgValuesSupported)
        try container.encodeIfPresent(dpopBoundAccessTokensRequired, forKey: .dpopBoundAccessTokensRequired)
    }
}

extension AuthorizationServerMetadata {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            issuer: try container.decode(String.self, forKey: .issuer),
            authorizationEndpoint: try container.decode(SafeURL.self, forKey: .authorizationEndpoint),
            tokenEndpoint: try container.decode(SafeURL.self, forKey: .tokenEndpoint),
            registrationEndpoint: try container.decodeOptional(SafeURL.self, forKey: .registrationEndpoint),
            authorizationResponseIssParameterSupported: try container.decodeOptional(Bool.self, forKey: .authorizationResponseIssParameterSupported),
            clientIdMetadataDocumentSupported: try container.decodeOptional(Bool.self, forKey: .clientIdMetadataDocumentSupported),
            scopesSupported: try container.decodeOptional([String].self, forKey: .scopesSupported),
            responseTypesSupported: try container.decode([String].self, forKey: .responseTypesSupported),
            grantTypesSupported: try container.decodeOptional([String].self, forKey: .grantTypesSupported),
            codeChallengeMethodsSupported: try container.decodeOptional([String].self, forKey: .codeChallengeMethodsSupported),
            tokenEndpointAuthMethodsSupported: try container.decodeOptional([String].self, forKey: .tokenEndpointAuthMethodsSupported),
            tokenEndpointAuthSigningAlgValuesSupported: try container.decodeOptional([String].self, forKey: .tokenEndpointAuthSigningAlgValuesSupported),
            userinfoEndpoint: try container.decodeOptional(SafeURL.self, forKey: .userinfoEndpoint),
            jwksUri: try container.decodeOptional(SafeURL.self, forKey: .jwksUri),
            subjectTypesSupported: try container.decodeOptional([String].self, forKey: .subjectTypesSupported),
            idTokenSigningAlgValuesSupported: try container.decodeOptional([String].self, forKey: .idTokenSigningAlgValuesSupported),
            claimsSupported: try container.decodeOptional([String].self, forKey: .claimsSupported),
            additionalProperties: try decodeAdditionalProperties(from: decoder, excluding: CodingKeys.self)
        )
    }

    public func encode(to encoder: Encoder) throws {
        try encodeAdditionalProperties(additionalProperties, to: encoder, excluding: CodingKeys.self)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(issuer, forKey: .issuer)
        try container.encode(authorizationEndpoint, forKey: .authorizationEndpoint)
        try container.encode(tokenEndpoint, forKey: .tokenEndpoint)
        try container.encodeIfPresent(registrationEndpoint, forKey: .registrationEndpoint)
        try container.encodeIfPresent(authorizationResponseIssParameterSupported, forKey: .authorizationResponseIssParameterSupported)
        try container.encodeIfPresent(clientIdMetadataDocumentSupported, forKey: .clientIdMetadataDocumentSupported)
        try container.encodeIfPresent(scopesSupported, forKey: .scopesSupported)
        try container.encode(responseTypesSupported, forKey: .responseTypesSupported)
        try container.encodeIfPresent(grantTypesSupported, forKey: .grantTypesSupported)
        try container.encodeIfPresent(codeChallengeMethodsSupported, forKey: .codeChallengeMethodsSupported)
        try container.encodeIfPresent(tokenEndpointAuthMethodsSupported, forKey: .tokenEndpointAuthMethodsSupported)
        try container.encodeIfPresent(tokenEndpointAuthSigningAlgValuesSupported, forKey: .tokenEndpointAuthSigningAlgValuesSupported)
        try container.encodeIfPresent(userinfoEndpoint, forKey: .userinfoEndpoint)
        try container.encodeIfPresent(jwksUri, forKey: .jwksUri)
        try container.encodeIfPresent(subjectTypesSupported, forKey: .subjectTypesSupported)
        try container.encodeIfPresent(idTokenSigningAlgValuesSupported, forKey: .idTokenSigningAlgValuesSupported)
        try container.encodeIfPresent(claimsSupported, forKey: .claimsSupported)
    }
}

extension OAuthClientInformation {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadataContainer = try decoder.container(keyedBy: OAuthClientMetadata.CodingKeys.self)
        self.init(
            clientId: try container.decode(String.self, forKey: .clientId),
            clientSecret: try container.decodeOptional(String.self, forKey: .clientSecret),
            clientIdIssuedAt: try container.decodeOptional(Double.self, forKey: .clientIdIssuedAt),
            clientSecretExpiresAt: try container.decodeOptional(Double.self, forKey: .clientSecretExpiresAt),
            issuer: try container.decodeOptional(SafeURL.self, forKey: .issuer),
            authorizationServer: try container.decodeOptional(SafeURL.self, forKey: .authorizationServer),
            tokenEndpoint: try container.decodeOptional(SafeURL.self, forKey: .tokenEndpoint),
            registrationMetadata: metadataContainer.contains(.redirectUris) ? try OAuthClientMetadata(from: decoder) : nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientId, forKey: .clientId)
        try container.encodeIfPresent(clientSecret, forKey: .clientSecret)
        try container.encodeIfPresent(clientIdIssuedAt, forKey: .clientIdIssuedAt)
        try container.encodeIfPresent(clientSecretExpiresAt, forKey: .clientSecretExpiresAt)
        try container.encodeIfPresent(issuer, forKey: .issuer)
        try container.encodeIfPresent(authorizationServer, forKey: .authorizationServer)
        try container.encodeIfPresent(tokenEndpoint, forKey: .tokenEndpoint)
        try registrationMetadata?.encode(to: encoder)
    }
}

extension OAuthClientMetadata {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            redirectUris: try container.decode([SafeURL].self, forKey: .redirectUris),
            applicationType: try container.decodeOptional(OAuthApplicationType.self, forKey: .applicationType),
            tokenEndpointAuthMethod: try container.decodeOptional(String.self, forKey: .tokenEndpointAuthMethod),
            grantTypes: try container.decodeOptional([String].self, forKey: .grantTypes),
            responseTypes: try container.decodeOptional([String].self, forKey: .responseTypes),
            clientName: try container.decodeOptional(String.self, forKey: .clientName),
            clientUri: try container.decodeOptional(SafeURL.self, forKey: .clientUri),
            logoUri: try container.decodeOptional(SafeURL.self, forKey: .logoUri),
            scope: try container.decodeOptional(String.self, forKey: .scope),
            contacts: try container.decodeOptional([String].self, forKey: .contacts),
            tosUri: try container.decodeOptional(SafeURL.self, forKey: .tosUri),
            policyUri: try container.decodeOptional(String.self, forKey: .policyUri),
            jwksUri: try container.decodeOptional(SafeURL.self, forKey: .jwksUri),
            jwks: try container.decodeOptional(JSONValue.self, forKey: .jwks),
            softwareId: try container.decodeOptional(String.self, forKey: .softwareId),
            softwareVersion: try container.decodeOptional(String.self, forKey: .softwareVersion),
            softwareStatement: try container.decodeOptional(String.self, forKey: .softwareStatement)
        )
    }
}

extension OAuthClientInformationFull {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadata = try OAuthClientMetadata(from: decoder)
        clientId = try container.decode(String.self, forKey: .clientId)
        clientSecret = try container.decodeOptional(String.self, forKey: .clientSecret)
        clientIdIssuedAt = try container.decodeOptional(Double.self, forKey: .clientIdIssuedAt)
        clientSecretExpiresAt = try container.decodeOptional(Double.self, forKey: .clientSecretExpiresAt)
        issuer = try container.decodeOptional(SafeURL.self, forKey: .issuer)
        authorizationServer = try container.decodeOptional(SafeURL.self, forKey: .authorizationServer)
        tokenEndpoint = try container.decodeOptional(SafeURL.self, forKey: .tokenEndpoint)
        redirectUris = metadata.redirectUris
        applicationType = metadata.applicationType
        tokenEndpointAuthMethod = metadata.tokenEndpointAuthMethod
        grantTypes = metadata.grantTypes
        responseTypes = metadata.responseTypes
        clientName = metadata.clientName
        clientUri = metadata.clientUri
        logoUri = metadata.logoUri
        scope = metadata.scope
        contacts = metadata.contacts
        tosUri = metadata.tosUri
        policyUri = metadata.policyUri
        jwksUri = metadata.jwksUri
        jwks = metadata.jwks
        softwareId = metadata.softwareId
        softwareVersion = metadata.softwareVersion
        softwareStatement = metadata.softwareStatement
    }
}

extension OAuthErrorResponse {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decode(String.self, forKey: .error)
        errorDescription = try container.decodeOptional(String.self, forKey: .errorDescription)
        errorUri = try container.decodeOptional(String.self, forKey: .errorUri)
    }
}
