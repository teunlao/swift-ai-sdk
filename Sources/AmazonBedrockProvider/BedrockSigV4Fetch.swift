
import Foundation
import CryptoKit
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-sigv4-fetch.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct BedrockCredentials: Sendable {
    public let region: String
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?

    public init(region: String, accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.region = region
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}

public func createSigV4FetchFunction(
    getCredentials: @escaping @Sendable () async throws -> BedrockCredentials,
    fetch: FetchFunction? = nil
) -> FetchFunction {
    let underlyingFetch = fetch ?? makeDefaultFetchFunction()

    return { request in
        var mutableRequest = request
        let url = try require(mutableRequest.url, message: "Bedrock request is missing URL")

        var headerMap = mutableRequest.allHTTPHeaderFields ?? [:]
        headerMap = withUserAgentSuffix(
            headerMap,
            "ai-sdk/amazon-bedrock/\(AMAZON_BEDROCK_VERSION)",
            getRuntimeEnvironmentUserAgent()
        )

        for (key, value) in headerMap {
            mutableRequest.setValue(value, forHTTPHeaderField: key)
        }

        let method = mutableRequest.httpMethod?.uppercased() ?? "GET"
        let bodyData = mutableRequest.httpBody ?? Data()

        guard method == "POST", !bodyData.isEmpty else {
            return try await underlyingFetch(mutableRequest)
        }

        let credentials = try await getCredentials()
        let now = Date()
        let amzDate = iso8601Timestamp(now)
        let dateStamp = shortDate(now)

        var signingHeaders = headerMap.mapKeys { $0.lowercased() }
        let payloadHash = sha256Hex(bodyData)
        signingHeaders["x-amz-date"] = amzDate
        signingHeaders["x-amz-content-sha256"] = payloadHash

        if let token = credentials.sessionToken, !token.isEmpty {
            signingHeaders["x-amz-security-token"] = token
        }

        if signingHeaders["host"] == nil {
            signingHeaders["host"] = hostHeader(from: url)
        }

        let canonicalRequest = buildCanonicalRequest(
            method: method,
            url: url,
            headers: signingHeaders,
            payloadHash: payloadHash
        )

        let canonicalRequestHash = sha256Hex(Data(canonicalRequest.utf8))
        let credentialScope = "\(dateStamp)/\(credentials.region)/bedrock/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        let signature = sign(
            stringToSign: stringToSign,
            dateStamp: dateStamp,
            region: credentials.region,
            service: "bedrock",
            secretAccessKey: credentials.secretAccessKey
        )

        let signedHeadersList = canonicalSignedHeaders(from: signingHeaders)
        signingHeaders["authorization"] = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeadersList), Signature=\(signature)"

        for (lowerKey, value) in signingHeaders {
            let originalKey = headerMap.first { $0.key.lowercased() == lowerKey }?.key ?? lowerKey
            mutableRequest.setValue(value, forHTTPHeaderField: originalKey)
        }

        if mutableRequest.value(forHTTPHeaderField: "Host") == nil {
            mutableRequest.setValue(hostHeader(from: url), forHTTPHeaderField: "Host")
        }

        return try await underlyingFetch(mutableRequest)
    }
}

public func createApiKeyFetchFunction(
    apiKey: String,
    fetch: FetchFunction? = nil
) -> FetchFunction {
    let underlyingFetch = fetch ?? makeDefaultFetchFunction()

    return { request in
        var mutableRequest = request
        var headers = mutableRequest.allHTTPHeaderFields ?? [:]
        headers = withUserAgentSuffix(
            headers,
            "ai-sdk/amazon-bedrock/\(AMAZON_BEDROCK_VERSION)",
            getRuntimeEnvironmentUserAgent()
        )
        headers["Authorization"] = "Bearer \(apiKey)"

        for (key, value) in headers {
            mutableRequest.setValue(value, forHTTPHeaderField: key)
        }

        return try await underlyingFetch(mutableRequest)
    }
}

// MARK: - Fetch Helper

private func makeDefaultFetchFunction() -> FetchFunction {
    if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
        return { request in
            let session = URLSession.shared
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
        }
    } else {
        return { request in
            let session = URLSession.shared
            let (data, response) = try await session.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }
}

// MARK: - Canonical Request Helpers

private func buildCanonicalRequest(
    method: String,
    url: URL,
    headers: [String: String],
    payloadHash: String
) -> String {
    let canonicalUri = canonicalURI(from: url)
    let canonicalQuery = canonicalQueryString(from: url)
    let canonicalHeaders = canonicalHeadersString(from: headers)
    let signedHeaders = canonicalSignedHeaders(from: headers)

    return [
        method,
        canonicalUri,
        canonicalQuery,
        canonicalHeaders,
        "",
        signedHeaders,
        payloadHash
    ].joined(separator: "\n")
}

private func canonicalURI(from url: URL) -> String {
    let path = url.path.isEmpty ? "/" : url.path
    return path.addingPercentEncoding(withAllowedCharacters: .awsSigV4PathAllowed) ?? path
}

private func canonicalQueryString(from url: URL) -> String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems, !queryItems.isEmpty else {
        return ""
    }

    let encoded = queryItems.map { item -> (String, String) in
        let name = percentEncode(item.name)
        let value = percentEncode(item.value ?? "")
        return (name, value)
    }
    .sorted { lhs, rhs in
        if lhs.0 == rhs.0 {
            return lhs.1 < rhs.1
        }
        return lhs.0 < rhs.0
    }
    .map { "\($0)=\($1)" }

    return encoded.joined(separator: "&")
}

private func canonicalHeadersString(from headers: [String: String]) -> String {
    let entries = headers
        .map { ($0.key.lowercased(), trimHeaderValue($0.value)) }
        .sorted { $0.0 < $1.0 }

    guard !entries.isEmpty else { return "" }
    return entries.map { "\($0.0):\($0.1)" }.joined(separator: "\n") + "\n"
}

private func canonicalSignedHeaders(from headers: [String: String]) -> String {
    headers.keys
        .map { $0.lowercased() }
        .sorted()
        .joined(separator: ";")
}

private func trimHeaderValue(_ value: String) -> String {
    let separators: Set<Character> = [" ", "\t", "\n", "\r"]
    return value
        .split(whereSeparator: { separators.contains($0) })
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func hostHeader(from url: URL) -> String {
    if let host = url.host {
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }
    return url.absoluteString
}

// MARK: - Signing Helpers

private func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func percentEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func sign(stringToSign: String, dateStamp: String, region: String, service: String, secretAccessKey: String) -> String {
    let kSecret = Data(("AWS4" + secretAccessKey).utf8)
    let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
    let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
    let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
    let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
    let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
    return signature.map { String(format: "%02x", $0) }.joined()
}

private func hmacSHA256(key: Data, data: Data) -> Data {
    let key = SymmetricKey(data: key)
    let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
    return Data(signature)
}

private func iso8601Timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: date)
}

private func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd"
    return formatter.string(from: date)
}

private func require<T>(_ value: T?, message: String) throws -> T {
    if let value {
        return value
    }
    throw APICallError(message: message, url: "", requestBodyValues: nil)
}

private extension Dictionary where Key == String, Value == String {
    func mapKeys(_ transform: (String) -> String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: map { key, value in (transform(key), value) })
    }
}

private extension CharacterSet {
    static let awsSigV4PathAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/%")
        return allowed
    }()
}
