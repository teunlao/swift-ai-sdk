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
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

private let GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL = "https://aiplatform.googleapis.com/v1/publishers/google"
private let GOOGLE_VERTEX_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"
private let GOOGLE_VERTEX_OAUTH_SCOPE = "https://www.googleapis.com/auth/cloud-platform"

let googleVertexHTTPRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^https?:\\/\\/.*$"
    )
}()

let googleVertexGCSRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^gs:\\/\\/.*$"
    )
}()

private func createExpressModeFetch(
    apiKey: String,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultFetchFunction()

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

actor GoogleVertexAccessTokenManager {
    private let credentialsOverride: GoogleVertexCredentials?
    private let fetch: FetchFunction
    private var cached: GoogleVertexAccessToken?

    init(credentials: GoogleVertexCredentials?, fetch: FetchFunction?) {
        self.credentialsOverride = credentials
        self.fetch = fetch ?? defaultFetchFunction()
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
            "ai-sdk-google-vertex/\(GOOGLE_VERTEX_VERSION)",
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

        let response = try await fetch(request)
        let data = try await response.body.collectData()
        guard let http = response.urlResponse as? HTTPURLResponse else {
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
        if let path = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"], !path.isEmpty {
            struct ServiceAccount: Decodable {
                let type: String
                let client_email: String
                let private_key: String
                let private_key_id: String?
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let account = try JSONDecoder().decode(ServiceAccount.self, from: data)
            guard account.type == "service_account", !account.client_email.isEmpty, !account.private_key.isEmpty else {
                throw LoadSettingError(message: "GOOGLE_APPLICATION_CREDENTIALS must reference a service_account key file with client_email and private_key")
            }
            return .init(clientEmail: account.client_email, privateKey: account.private_key, privateKeyId: account.private_key_id)
        }
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

    let isPKCS8 = normalized.contains("-----BEGIN PRIVATE KEY-----")
    let stripped = normalized
        .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
        .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
        .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
        .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()

    guard let keyData = Data(base64Encoded: stripped) else {
        throw LoadSettingError(message: "Failed to load Google credentials: invalid private key PEM")
    }

    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
    ]

    let rsaData = try isPKCS8 ? unwrapPKCS8(keyData) : keyData
    var error: Unmanaged<CFError>?
    guard let secKey = SecKeyCreateWithData(rsaData as CFData, attributes as CFDictionary, &error) else {
        throw (error?.takeRetainedValue() ?? LoadSettingError(message: "Failed to load Google credentials: invalid private key"))
    }

    return secKey
}

private func unwrapPKCS8(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    let invalid = LoadSettingError(message: "Failed to load Google credentials: invalid RSA PKCS8 private key")
    func read(_ tag: UInt8, offset: inout Int, end: Int) throws -> Range<Int> {
        guard offset + 2 <= end, bytes[offset] == tag else { throw invalid }
        offset += 1
        var length = Int(bytes[offset])
        offset += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, offset + count <= end else { throw invalid }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[offset])
                offset += 1
            }
        }
        guard length <= end - offset else { throw invalid }
        let range = offset..<(offset + length)
        offset += length
        return range
    }
    var offset = 0
    let sequence = try read(0x30, offset: &offset, end: bytes.count)
    guard offset == bytes.count else { throw invalid }
    offset = sequence.lowerBound
    _ = try read(0x02, offset: &offset, end: sequence.upperBound)
    let algorithm = try read(0x30, offset: &offset, end: sequence.upperBound)
    var algorithmOffset = algorithm.lowerBound
    let oid = try read(0x06, offset: &algorithmOffset, end: algorithm.upperBound)
    guard Array(bytes[oid]) == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01] else { throw invalid }
    let key = try read(0x04, offset: &offset, end: sequence.upperBound)
    return Data(bytes[key])
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
    let baseFetch = customFetch ?? defaultFetchFunction()

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

func isVertexHostnamePart(_ value: String) -> Bool {
    guard let range = value.range(of: "^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$", options: .regularExpression) else { return false }
    return range == value.startIndex..<value.endIndex
}

func vertexHost(_ location: String) -> String {
    switch location {
    case "global": "aiplatform.googleapis.com"
    case "eu", "us": "aiplatform.\(location).rep.googleapis.com"
    default: "\(location)-aiplatform.googleapis.com"
    }
}

public struct GoogleVertexProviderSettings: Sendable {
    public struct ToolResultDownloads: Sendable {
        public var maxBytes: Int
        public init(maxBytes: Int = 7 * 1024 * 1024) { self.maxBytes = maxBytes }
    }
    public var toolResultDownloads: ToolResultDownloads?
    /// Optional. The API key for the Google Cloud project. If provided, the provider will use express mode with API key authentication.
    /// Defaults to the value of the `GOOGLE_VERTEX_API_KEY` environment variable.
    public var apiKey: String?

    public var location: String?
    public var project: String?
    public var headers: [String: String]?
    public var headersProvider: (@Sendable () async throws -> [String: String?])?
    public var webSocket: GoogleWebSocketFactory?
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
        accessTokenProvider: (@Sendable () async throws -> String)? = nil,
        toolResultDownloads: ToolResultDownloads? = nil,
        headersProvider: (@Sendable () async throws -> [String: String?])? = nil,
        webSocket: GoogleWebSocketFactory? = nil
    ) {
        self.apiKey = apiKey
        self.location = location
        self.project = project
        self.headers = headers
        self.headersProvider = headersProvider
        self.webSocket = webSocket
        self.fetch = fetch
        self.generateId = generateId
        self.baseURL = baseURL
        self.googleCredentials = googleCredentials
        self.accessTokenProvider = accessTokenProvider
        self.toolResultDownloads = toolResultDownloads
    }
}

public final class GoogleVertexProvider: ProviderV4 {
    private let languageFactory: @Sendable (GoogleVertexModelId) -> GoogleLanguageModel
    private let embeddingFactory: @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel
    private let imageFactory: @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel
    private let videoFactory: @Sendable (GoogleVertexVideoModelId) -> GoogleVertexVideoModel
    private let speechFactory: @Sendable (String) -> any SpeechModelV4
    private let transcriptionFactory: @Sendable (String) -> any TranscriptionModelV4
    private let interactionsFactory: @Sendable (GoogleInteractionsModelInput) -> GoogleInteractionsLanguageModel

    public let tools: GoogleVertexTools

    init(
        language: @escaping @Sendable (GoogleVertexModelId) -> GoogleLanguageModel,
        embedding: @escaping @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel,
        image: @escaping @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel,
        video: @escaping @Sendable (GoogleVertexVideoModelId) -> GoogleVertexVideoModel,
        speech: @escaping @Sendable (String) -> any SpeechModelV4,
        transcription: @escaping @Sendable (String) -> any TranscriptionModelV4,
        interactions: @escaping @Sendable (GoogleInteractionsModelInput) -> GoogleInteractionsLanguageModel,
        tools: GoogleVertexTools
    ) {
        self.languageFactory = language
        self.embeddingFactory = embedding
        self.imageFactory = image
        self.videoFactory = video
        self.speechFactory = speech
        self.transcriptionFactory = transcription
        self.interactionsFactory = interactions
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        return languageFactory(GoogleVertexModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embeddingFactory(GoogleVertexEmbeddingModelId(rawValue: modelId))
    }

    public func interactions(modelId: GoogleInteractionsModelId) -> GoogleInteractionsLanguageModel { interactionsFactory(.model(modelId.rawValue)) }
    public func interactions(_ input: GoogleInteractionsModelInput) -> GoogleInteractionsLanguageModel { interactionsFactory(input) }

    public func speech(modelId: String) -> any SpeechModelV4 { speechFactory(modelId) }
    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? { speechFactory(modelId) }
    public func transcription(modelId: String) -> any TranscriptionModelV4 { transcriptionFactory(modelId) }
    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? { transcriptionFactory(modelId) }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        return imageFactory(GoogleVertexImageModelId(rawValue: modelId))
    }

    public func videoModel(modelId: String) throws -> (any VideoModelV4)? {
        return videoFactory(GoogleVertexVideoModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience Accessors

    public func languageModel(modelId: GoogleVertexModelId) -> GoogleLanguageModel {
        return languageFactory(modelId)
    }

    public func embeddingModel(modelId: GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel {
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
    ).flatMap { $0.isEmpty ? nil : $0 }

    let loadProject: @Sendable () throws -> String = {
        try loadSetting(
            settingValue: settings.project,
            environmentVariableName: "GOOGLE_VERTEX_PROJECT",
            settingName: "project",
            description: "Google Vertex project"
        )
    }

    let loadLocation: @Sendable () throws -> String = {
        let location = try loadSetting(
            settingValue: settings.location,
            environmentVariableName: "GOOGLE_VERTEX_LOCATION",
            settingName: "location",
            description: "Google Vertex location"
        )
        guard isVertexHostnamePart(location) else {
            throw InvalidArgumentError(argument: "location", message: "Invalid Google Vertex location. Expected a single DNS label (letters, digits, and hyphens). Use `baseURL` for custom endpoints.")
        }
        return location
    }

    let loadBaseURL: @Sendable (Bool) throws -> String = { endpoint in
        if let baseURL = withoutTrailingSlash(settings.baseURL) { return baseURL }
        if apiKey != nil { return GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL }
        let location = try loadLocation()
        let project = try loadProject()
        let host = vertexHost(location)
        return "https://\(host)/v1beta1/projects/\(project)/locations/\(location)\(endpoint ? "" : "/publishers/google")"
    }

    let resolvedBaseURL = withoutTrailingSlash(settings.baseURL) ?? GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL

    let headersClosure: @Sendable () throws -> [String: String?] = {
        _ = try loadBaseURL(false)

        var computed: [String: String?] = [:]
        if let provided = settings.headers {
            for (key, value) in provided {
                computed[key] = value
            }
        }

        if settings.headersProvider != nil { return computed }
        let withUA = withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk-google-vertex/\(GOOGLE_VERTEX_VERSION)"
        )

        return withUA.mapValues { Optional($0) }
    }

    let supportedURLs: @Sendable () -> [String: [NSRegularExpression]] = {
        ["*": [googleVertexHTTPRegex, googleVertexGCSRegex]]
    }

    let baseURLProvided = withoutTrailingSlash(settings.baseURL) != nil

    let tokenManager = GoogleVertexAccessTokenManager(credentials: settings.googleCredentials, fetch: settings.fetch)
    let accessToken: @Sendable () async throws -> String = {
        if let provider = settings.accessTokenProvider { return try await provider() }
        return try await tokenManager.getToken()
    }
    let authenticatedFetch: FetchFunction? = {
        if let apiKey {
            return createExpressModeFetch(apiKey: apiKey, customFetch: settings.fetch)
        }

        // Custom gateways may own authentication; explicit credentials still apply.
        if baseURLProvided && settings.googleCredentials == nil && settings.accessTokenProvider == nil {
            return settings.fetch
        }

        return createBearerTokenFetch(accessToken: accessToken, customFetch: settings.fetch)
    }()

    let fetch: FetchFunction? = settings.headersProvider.map { resolveHeaders in
        let baseFetch = authenticatedFetch ?? defaultFetchFunction()
        return { request in
            let dynamicHeaders = try await resolveHeaders()
            var modified = request
            let merged = combineHeaders(dynamicHeaders, request.allHTTPHeaderFields).compactMapValues { $0 }
            modified.allHTTPHeaderFields = withUserAgentSuffix(merged, "ai-sdk-google-vertex/\(GOOGLE_VERTEX_VERSION)")
            return try await baseFetch(modified)
        }
    } ?? authenticatedFetch

    let generateId = settings.generateId

    let languageFactory: @Sendable (GoogleVertexModelId) -> GoogleLanguageModel = { modelId in
        let endpoint = modelId.rawValue.hasPrefix("endpoints/")
        return GoogleLanguageModel(
            modelId: GoogleModelId(rawValue: modelId.rawValue),
            config: GoogleLanguageModel.Config(
                provider: "google.vertex.chat",
                baseURL: resolvedBaseURL,
                headers: {
                    if endpoint && apiKey != nil {
                        throw InvalidArgumentError(argument: "modelId", message: "Google Vertex tuned models do not support Express Mode API keys. Use standard Google Cloud credentials instead.")
                    }
                    return try headersClosure()
                },
                fetch: fetch,
                generateId: generateId,
                supportedUrls: supportedURLs,
                downloadToolResultFiles: .init(maxBytes: settings.toolResultDownloads?.maxBytes ?? 7 * 1024 * 1024, supportsGoogleCloudStorageUrls: true),
                resolveBaseURL: { try loadBaseURL(endpoint) }
            )
        )
    }

    let embeddingFactory: @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel = { modelId in
        GoogleVertexEmbeddingModel(
            modelId: modelId,
            config: GoogleVertexEmbeddingConfig(
                provider: "google.vertex.embedding",
                baseURL: { try loadBaseURL(false) },
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
                baseURL: { try loadBaseURL(false) },
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
                baseURL: { try loadBaseURL(false) },
                headers: headersClosure,
                fetch: fetch,
                generateId: generateId
            )
        )
    }

    let speechFactory: @Sendable (String) -> any SpeechModelV4 = { modelId in
        if modelId.hasPrefix("chirp") {
            return GoogleVertexCloudTTSSpeechModel(modelId: modelId, config: .init(
                provider: "google.vertex.speech",
                headers: {
                    if apiKey != nil {
                        throw InvalidArgumentError(argument: "modelId", message: "Google Vertex Chirp speech models do not support Express Mode API keys. Use standard Google Cloud credentials instead.")
                    }
                    return try headersClosure()
                }, fetch: fetch
            ))
        }
        return GoogleSpeechModel(modelId: modelId, config: .init(
            provider: "google.vertex.speech", baseURL: resolvedBaseURL, headers: headersClosure, fetch: fetch,
            resolveBaseURL: { try loadBaseURL(false) }
        ))
    }
    let transcriptionFactory: @Sendable (String) -> any TranscriptionModelV4 = { modelId in
        let transcriptionHeaders: @Sendable () throws -> [String: String?] = {
            if apiKey != nil {
                throw InvalidArgumentError(argument: "modelId", message: "Google Vertex transcription models do not support Express Mode API keys. Use standard Google Cloud credentials instead.")
            }
            return try headersClosure()
        }
        if modelId.hasPrefix("gemini") {
            return GoogleVertexGeminiTranscriptionModel(modelId: modelId, config: .init(
                provider: "google.vertex.transcription", baseURL: resolvedBaseURL, headers: transcriptionHeaders, fetch: fetch,
                resolveBaseURL: { try loadBaseURL(false) }, webSocket: settings.webSocket,
                liveRequest: { modelId, headers in
                    let project = try loadProject()
                    let location = try loadLocation()
                    let host = vertexHost(location)
                    var resolved = combineHeaders(try await settings.headersProvider?(), headers).compactMapValues { $0 }
                    if !resolved.keys.contains(where: { $0.lowercased() == "authorization" }) {
                        resolved["Authorization"] = "Bearer \(try await accessToken())"
                    }
                    let url = try requireURL("wss://\(host)/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent")
                    return .init(url: url, model: "projects/\(project)/locations/\(location)/publishers/google/models/\(modelId)", headers: resolved)
                }
            ))
        }
        return GoogleVertexTranscriptionModel(modelId: modelId, config: .init(
            provider: "google.vertex.transcription", project: loadProject, location: loadLocation,
            headers: transcriptionHeaders, fetch: fetch, isExpressMode: apiKey != nil
        ))
    }
    let interactionsFactory: @Sendable (GoogleInteractionsModelInput) -> GoogleInteractionsLanguageModel = { input in
        GoogleInteractionsLanguageModel(input: input, config: .init(
            provider: "google.vertex.interactions", baseURL: resolvedBaseURL,
            headers: {
                if apiKey != nil {
                    throw InvalidArgumentError(argument: "modelId", message: "Google Vertex Interactions models do not support Express Mode API keys. Use standard Google Cloud credentials instead.")
                }
                return try headersClosure()
            }, fetch: fetch, generateId: generateId, resolveBaseURL: { try loadBaseURL(true) }
        ))
    }
    return GoogleVertexProvider(
        language: languageFactory,
        embedding: embeddingFactory,
        image: imageFactory,
        video: videoFactory,
        speech: speechFactory,
        transcription: transcriptionFactory,
        interactions: interactionsFactory,
        tools: googleVertexTools
    )
}

public let googleVertex = createGoogleVertex()
