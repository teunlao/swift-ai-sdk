import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleVertexPartnerSettings: Sendable {
    public var project: String?
    public var location: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var headersProvider: (@Sendable () async throws -> [String: String?])?
    public var fetch: FetchFunction?
    public var googleCredentials: GoogleVertexCredentials?
    public var generateAuthToken: (@Sendable () async throws -> String?)?

    public init(project: String? = nil, location: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, headersProvider: (@Sendable () async throws -> [String: String?])? = nil, fetch: FetchFunction? = nil, googleCredentials: GoogleVertexCredentials? = nil, generateAuthToken: (@Sendable () async throws -> String?)? = nil) {
        self.project = project; self.location = location; self.baseURL = baseURL
        self.headers = headers; self.headersProvider = headersProvider; self.fetch = fetch
        self.googleCredentials = googleCredentials; self.generateAuthToken = generateAuthToken
    }
}

public typealias GoogleVertexAnthropicProviderSettings = GoogleVertexPartnerSettings
public typealias GoogleVertexMaasProviderSettings = GoogleVertexPartnerSettings
public typealias GoogleVertexXaiProviderSettings = GoogleVertexPartnerSettings

struct VertexPartnerConfig: Sendable {
    enum API: Sendable, Equatable { case anthropic, maas, xai }
    let settings: GoogleVertexPartnerSettings
    private let tokens: GoogleVertexAccessTokenManager

    init(_ settings: GoogleVertexPartnerSettings) {
        self.settings = settings
        tokens = GoogleVertexAccessTokenManager(credentials: settings.googleCredentials, fetch: settings.fetch)
    }

    func baseURL(_ api: API) throws -> String {
        if let url = withoutTrailingSlash(settings.baseURL) { return url }
        let project = try loadSetting(settingValue: settings.project, environmentVariableName: "GOOGLE_VERTEX_PROJECT", settingName: "project", description: "Google Vertex project")
        let location = try loadOptionalSetting(settingValue: settings.location, environmentVariableName: "GOOGLE_VERTEX_LOCATION") ?? {
            if api == .anthropic {
                throw LoadSettingError(message: "Google Vertex location setting is missing")
            }
            return "global"
        }()
        if api != .xai, !isVertexHostnamePart(location) {
            throw InvalidArgumentError(argument: "location", message: "Invalid Google Vertex location. Expected a single DNS label (letters, digits, and hyphens). Use `baseURL` for custom endpoints.")
        }
        let host = api == .xai ? "aiplatform.googleapis.com" : vertexHost(location)
        let suffix = api == .anthropic ? "publishers/anthropic/models" : "endpoints/openapi"
        return "https://\(host)/v1/projects/\(project)/locations/\(location)/\(suffix)"
    }

    func headers(callerOverridesAuth: Bool) async throws -> [String: String?] {
        let configured = combineHeaders(settings.headers, try await settings.headersProvider?())
        if withoutTrailingSlash(settings.baseURL) != nil && settings.googleCredentials == nil && settings.generateAuthToken == nil {
            return configured
        }
        let token: String?
        if let generator = settings.generateAuthToken { token = try await generator() }
        else { token = try await tokens.getToken() }
        let authorization: [String: String?] = ["Authorization": "Bearer \(token ?? "null")"]
        return callerOverridesAuth ? combineHeaders(authorization, configured) : combineHeaders(configured, authorization)
    }

    func fetch() -> FetchFunction {
        let transport = settings.fetch ?? defaultFetchFunction()
        return { request in
            var authenticated = request
            authenticated.allHTTPHeaderFields = combineHeaders(request.allHTTPHeaderFields, try await headers(callerOverridesAuth: false)).compactMapValues { $0 }
            return try await transport(authenticated)
        }
    }
}
