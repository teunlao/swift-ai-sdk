import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider
import Security

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-provider.ts
// Ported from packages/google-vertex/src/google-vertex-provider-node.ts
// Ported from packages/google-vertex/src/edge/google-vertex-auth-edge.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

private let GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL = "https://aiplatform.googleapis.com/v1/publishers/google"
private let GOOGLE_VERTEX_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"
private let GOOGLE_VERTEX_OAUTH_SCOPE = "https://www.googleapis.com/auth/cloud-platform"

private let googleVertexHTTPRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^https?:\\/\\/.*$"
    )
}()

private let googleVertexGCSRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^gs:\\/\\/.*$"
    )
}()

private func defaultGoogleVertexFetchFunction() -> FetchFunction {
    { request in
        let session = URLSession.shared

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            let (bytes, response) = try await session.bytes(for: request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                Task {
                    var buffer = Data()
                    buffer.reserveCapacity(16_384)

                    do {
                        for try await byte in bytes {
                            buffer.append(byte)

                            if buffer.count >= 16_384 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }

                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            return FetchResponse(body: .stream(stream), urlResponse: response)
        } else {
            let (data, response) = try await session.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }
}

private func createExpressModeFetch(
    apiKey: String,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultGoogleVertexFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]
        let keysToRemove = headers.keys.filter { $0.lowercased() == "x-goog-api-key" }
        for key in keysToRemove {
            headers.removeValue(forKey: key)
        }
        headers["x-goog-api-key"] = apiKey
        modified.allHTTPHeaderFields = headers
        return try await baseFetch(modified)
    }
}

public struct GoogleVertexCredentials: Sendable, Equatable {
    /// The client email for the Google Cloud service account.
    /// Defaults to the `GOOGLE_CLIENT_EMAIL` environment variable.
    public var clientEmail: String

    /// The private key PEM for the Google Cloud service account.
    /// Defaults to the `GOOGLE_PRIVATE_KEY` environment variable.
    public var privateKey: String

    /// Optional. The private key ID for the Google Cloud service account.
    /// Defaults to the `GOOGLE_PRIVATE_KEY_ID` environment variable.
    public var privateKeyId: String?

    public init(
        clientEmail: String,
        privateKey: String,
        privateKeyId: String? = nil
    ) {
        self.clientEmail = clientEmail
        self.privateKey = privateKey
        self.privateKeyId = privateKeyId
    }
}

private struct GoogleVertexAccessToken: Sendable {
    let value: String
    let expiresAt: Date
}

private actor GoogleVertexAccessTokenManager {
    private let credentialsOverride: GoogleVertexCredentials?
    private var cached: GoogleVertexAccessToken?

    init(credentials: GoogleVertexCredentials?) {
        self.credentialsOverride = credentials
    }

    func getToken(now: Date = Date()) async throws -> String {
        if let cached, cached.expiresAt.timeIntervalSince(now) > 60 {
            return cached.value
        }

        let token = try await fetchAccessToken(now: now)
        cached = token
        return token.value
    }

    private func fetchAccessToken(now: Date) async throws -> GoogleVertexAccessToken {
        let creds = try loadGoogleVertexCredentials(credentialsOverride)
        let jwt = try buildGoogleVertexServiceAccountJWT(credentials: creds, now: now)

        var request = URLRequest(url: try requireURL(GOOGLE_VERTEX_OAUTH_TOKEN_URL))
        request.httpMethod = "POST"

        let headers = withUserAgentSuffix(
            ["Content-Type": "application/x-www-form-urlencoded"],
            "ai-sdk/google-vertex/\(GOOGLE_VERTEX_VERSION)",
            getRuntimeEnvironmentUserAgent()
        )
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body = formURLEncodedBody([
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": jwt
        ])
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APICallError(
                message: "Token request failed: invalid response type",
                url: GOOGLE_VERTEX_OAUTH_TOKEN_URL,
                requestBodyValues: nil
            )
        }

        guard (200...299).contains(http.statusCode) else {
            let statusText = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APICallError(
                message: "Token request failed: \(statusText)",
                url: GOOGLE_VERTEX_OAUTH_TOKEN_URL,
                requestBodyValues: nil,
                statusCode: http.statusCode,
                responseHeaders: extractResponseHeaders(from: http),
                responseBody: String(data: data, encoding: .utf8)
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken = json?["access_token"] as? String, !accessToken.isEmpty else {
            throw APICallError(
                message: "Token request failed: missing access_token",
                url: GOOGLE_VERTEX_OAUTH_TOKEN_URL,
                requestBodyValues: nil,
                statusCode: http.statusCode,
                responseHeaders: extractResponseHeaders(from: http),
                responseBody: String(data: data, encoding: .utf8)
            )
        }

        let expiresIn = (json?["expires_in"] as? Double) ?? 3600
        return GoogleVertexAccessToken(value: accessToken, expiresAt: now.addingTimeInterval(expiresIn))
    }
}

private func requireURL(_ urlString: String) throws -> URL {
    guard let url = URL(string: urlString) else {
        throw APICallError(message: "Invalid URL", url: urlString, requestBodyValues: nil)
    }
    return url
}

private func loadGoogleVertexCredentials(_ override: GoogleVertexCredentials?) throws -> GoogleVertexCredentials {
    if let override {
        return override
    }

    do {
        return GoogleVertexCredentials(
            clientEmail: try loadSetting(
                settingValue: nil,
                environmentVariableName: "GOOGLE_CLIENT_EMAIL",
                settingName: "clientEmail",
                description: "Google client email"
            ),
            privateKey: try loadSetting(
                settingValue: nil,
                environmentVariableName: "GOOGLE_PRIVATE_KEY",
                settingName: "privateKey",
                description: "Google private key"
            ),
            privateKeyId: loadOptionalSetting(
                settingValue: nil,
                environmentVariableName: "GOOGLE_PRIVATE_KEY_ID"
            )
        )
    } catch let error as LoadSettingError {
        throw LoadSettingError(message: "Failed to load Google credentials: \(error.message)")
    } catch {
        throw LoadSettingError(message: "Failed to load Google credentials: \(error)")
    }
}

private func buildGoogleVertexServiceAccountJWT(
    credentials: GoogleVertexCredentials,
    now: Date
) throws -> String {
    let nowSeconds = Int(now.timeIntervalSince1970)

    var header: [String: Any] = [
        "alg": "RS256",
        "typ": "JWT"
    ]
    if let kid = credentials.privateKeyId, !kid.isEmpty {
        header["kid"] = kid
    }

    let payload: [String: Any] = [
        "iss": credentials.clientEmail,
        "scope": GOOGLE_VERTEX_OAUTH_SCOPE,
        "aud": GOOGLE_VERTEX_OAUTH_TOKEN_URL,
        "exp": nowSeconds + 3600,
        "iat": nowSeconds
    ]

    let headerPart = try base64urlEncodeJSON(header)
    let payloadPart = try base64urlEncodeJSON(payload)
    let signingInput = "\(headerPart).\(payloadPart)"

    let signature = try signRS256(message: Data(signingInput.utf8), privateKeyPEM: credentials.privateKey)
    let signaturePart = base64urlEncode(signature)

    return "\(headerPart).\(payloadPart).\(signaturePart)"
}

private func base64urlEncodeJSON(_ value: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [])
    return base64urlEncode(data)
}

private func base64urlEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func signRS256(message: Data, privateKeyPEM: String) throws -> Data {
    let key = try importRSAPrivateKey(pem: privateKeyPEM)
    var error: Unmanaged<CFError>?

    guard let signature = SecKeyCreateSignature(
        key,
        .rsaSignatureMessagePKCS1v15SHA256,
        message as CFData,
        &error
    ) else {
        throw (error?.takeRetainedValue() ?? NSError(
            domain: "GoogleVertexProvider.SignatureError",
            code: -1
        ))
    }

    return signature as Data
}

private func importRSAPrivateKey(pem: String) throws -> SecKey {
    // Environment variables often encode newlines as literal `\n`.
    let normalized = pem.replacingOccurrences(of: "\\n", with: "\n")

    let pemHeader = "-----BEGIN PRIVATE KEY-----"
    let pemFooter = "-----END PRIVATE KEY-----"

    let stripped = normalized
        .replacingOccurrences(of: pemHeader, with: "")
        .replacingOccurrences(of: pemFooter, with: "")
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()

    guard let keyData = Data(base64Encoded: stripped) else {
        throw LoadSettingError(message: "Failed to load Google credentials: invalid private key PEM")
    }

    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
    ]

    var error: Unmanaged<CFError>?
    guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
        throw (error?.takeRetainedValue() ?? LoadSettingError(message: "Failed to load Google credentials: invalid private key"))
    }

    return secKey
}

private func formURLEncodedBody(_ fields: [String: String]) -> Data {
    // RFC 3986 unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")

    let formString = fields
        .map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .joined(separator: "&")

    return Data(formString.utf8)
}

private func createBearerTokenFetch(
    accessToken: @escaping @Sendable () async throws -> String,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultGoogleVertexFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            let token = try await accessToken()
            headers["Authorization"] = "Bearer \(token)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public struct GoogleVertexProviderSettings: Sendable {
    /// Optional. The API key for the Google Cloud project. If provided, the provider will use express mode with API key authentication.
    /// Defaults to the value of the `GOOGLE_VERTEX_API_KEY` environment variable.
    public var apiKey: String?

    public var location: String?
    public var project: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: @Sendable () -> String
    public var baseURL: String?
    public var googleCredentials: GoogleVertexCredentials?
    public var accessTokenProvider: (@Sendable () async throws -> String)?

    public init(
        apiKey: String? = nil,
        location: String? = nil,
        project: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: @escaping @Sendable () -> String = generateID,
        baseURL: String? = nil,
        googleCredentials: GoogleVertexCredentials? = nil,
        accessTokenProvider: (@Sendable () async throws -> String)? = nil
    ) {
        self.apiKey = apiKey
        self.location = location
        self.project = project
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
        self.baseURL = baseURL
        self.googleCredentials = googleCredentials
        self.accessTokenProvider = accessTokenProvider
    }
}

public final class GoogleVertexProvider: ProviderV3 {
    private let languageFactory: @Sendable (GoogleVertexModelId) -> GoogleGenerativeAILanguageModel
    private let embeddingFactory: @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel
    private let imageFactory: @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel
    private let videoFactory: @Sendable (GoogleVertexVideoModelId) -> GoogleVertexVideoModel

    public let tools: GoogleVertexTools

    init(
        language: @escaping @Sendable (GoogleVertexModelId) -> GoogleGenerativeAILanguageModel,
        embedding: @escaping @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel,
        image: @escaping @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel,
        video: @escaping @Sendable (GoogleVertexVideoModelId) -> GoogleVertexVideoModel,
        tools: GoogleVertexTools
    ) {
        self.languageFactory = language
        self.embeddingFactory = embedding
        self.imageFactory = image
        self.videoFactory = video
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        return languageFactory(GoogleVertexModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        return embeddingFactory(GoogleVertexEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        return imageFactory(GoogleVertexImageModelId(rawValue: modelId))
    }

    public func videoModel(modelId: String) throws -> (any VideoModelV3)? {
        return videoFactory(GoogleVertexVideoModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience Accessors

    public func languageModel(modelId: GoogleVertexModelId) -> GoogleGenerativeAILanguageModel {
        return languageFactory(modelId)
    }

    public func chat(modelId: GoogleVertexModelId) -> GoogleGenerativeAILanguageModel {
        return languageFactory(modelId)
    }

    public func embeddingModel(modelId: GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel {
        return embeddingFactory(modelId)
    }

    public func textEmbeddingModel(modelId: GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel {
        return embeddingFactory(modelId)
    }

    public func textEmbedding(modelId: GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel {
        return embeddingFactory(modelId)
    }

    public func image(modelId: GoogleVertexImageModelId) -> GoogleVertexImageModel {
        return imageFactory(modelId)
    }

    public func imageModel(modelId: GoogleVertexImageModelId) -> GoogleVertexImageModel {
        return imageFactory(modelId)
    }

    public func video(modelId: GoogleVertexVideoModelId) -> GoogleVertexVideoModel {
        return videoFactory(modelId)
    }

    public func videoModel(modelId: GoogleVertexVideoModelId) -> GoogleVertexVideoModel {
        return videoFactory(modelId)
    }
}

public func createGoogleVertex(settings: GoogleVertexProviderSettings = .init()) -> GoogleVertexProvider {
    let apiKey = loadOptionalSetting(
        settingValue: settings.apiKey,
        environmentVariableName: "GOOGLE_VERTEX_API_KEY"
    )

    let loadProject: () throws -> String = {
        try loadSetting(
            settingValue: settings.project,
            environmentVariableName: "GOOGLE_VERTEX_PROJECT",
            settingName: "project",
            description: "Google Vertex project"
        )
    }

    let loadLocation: () throws -> String = {
        try loadSetting(
            settingValue: settings.location,
            environmentVariableName: "GOOGLE_VERTEX_LOCATION",
            settingName: "location",
            description: "Google Vertex location"
        )
    }

    let baseURLResolution: Result<String, any Error> = {
        do {
            if let baseURL = withoutTrailingSlash(settings.baseURL) {
                return .success(baseURL)
            }

            if apiKey != nil {
                return .success(GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL)
            }

            let location = try loadLocation()
            let project = try loadProject()

            let hostPrefix = location == "global" ? "" : "\(location)-"
            let baseHost = "\(hostPrefix)aiplatform.googleapis.com"
            return .success("https://\(baseHost)/v1beta1/projects/\(project)/locations/\(location)/publishers/google")
        } catch {
            return .failure(error)
        }
    }()

    let resolvedBaseURL: String = (try? baseURLResolution.get()) ?? GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL

    let headersClosure: @Sendable () throws -> [String: String?] = {
        if case .failure(let error) = baseURLResolution {
            throw error
        }

        var computed: [String: String?] = [:]
        if let provided = settings.headers {
            for (key, value) in provided {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/google-vertex/\(GOOGLE_VERTEX_VERSION)"
        )

        return withUA.mapValues { Optional($0) }
    }

    let supportedURLs: @Sendable () -> [String: [NSRegularExpression]] = {
        ["*": [googleVertexHTTPRegex, googleVertexGCSRegex]]
    }

    let baseURLProvided = withoutTrailingSlash(settings.baseURL) != nil

    let fetch: FetchFunction? = {
        if let apiKey {
            return createExpressModeFetch(apiKey: apiKey, customFetch: settings.fetch)
        }

        // Intentional deviation (baseURL bypass): when a custom baseURL is provided,
        // do not require project/location and do not attempt to auto-inject OAuth.
        if baseURLProvided {
            return settings.fetch
        }

        let tokenManager = GoogleVertexAccessTokenManager(credentials: settings.googleCredentials)
        let accessToken: @Sendable () async throws -> String = {
            if let provider = settings.accessTokenProvider {
                return try await provider()
            }
            return try await tokenManager.getToken()
        }

        return createBearerTokenFetch(accessToken: accessToken, customFetch: settings.fetch)
    }()

    let generateId = settings.generateId

    let languageFactory: @Sendable (GoogleVertexModelId) -> GoogleGenerativeAILanguageModel = { modelId in
        GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: modelId.rawValue),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.vertex.chat",
                baseURL: resolvedBaseURL,
                headers: headersClosure,
                fetch: fetch,
                generateId: generateId,
                supportedUrls: supportedURLs
            )
        )
    }

    let embeddingFactory: @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel = { modelId in
        GoogleVertexEmbeddingModel(
            modelId: modelId,
            config: GoogleVertexEmbeddingConfig(
                provider: "google.vertex.embedding",
                baseURL: resolvedBaseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    let imageFactory: @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel = { modelId in
        GoogleVertexImageModel(
            modelId: modelId,
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: resolvedBaseURL,
                headers: headersClosure,
                fetch: fetch,
                generateId: generateId,
                currentDate: { Date() }
            )
        )
    }

    let videoFactory: @Sendable (GoogleVertexVideoModelId) -> GoogleVertexVideoModel = { modelId in
        GoogleVertexVideoModel(
            modelId: modelId,
            config: GoogleVertexVideoModelConfig(
                provider: "google.vertex.video",
                baseURL: resolvedBaseURL,
                headers: headersClosure,
                fetch: fetch,
                generateId: generateId
            )
        )
    }

    return GoogleVertexProvider(
        language: languageFactory,
        embedding: embeddingFactory,
        image: imageFactory,
        video: videoFactory,
        tools: googleVertexTools
    )
}

public func createVertex(settings: GoogleVertexProviderSettings = .init()) -> GoogleVertexProvider {
    createGoogleVertex(settings: settings)
}

public let googleVertex = createGoogleVertex()
public let vertex = createVertex()
