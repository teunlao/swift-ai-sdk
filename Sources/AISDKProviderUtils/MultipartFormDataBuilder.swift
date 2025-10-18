import Foundation

/// Utility to build multipart/form-data payloads.
///
/// Port of the minimal functionality used by `@ai-sdk/provider-utils/src/post-to-api.ts`
/// for constructing multipart requests.
public struct MultipartFormDataBuilder: Sendable {
    private struct Part: Sendable {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
    }

    public let boundary: String
    private var parts: [Part] = []

    public init(boundary: String = MultipartFormDataBuilder.makeBoundary()) {
        self.boundary = boundary
    }

    /// Appends a simple text field to the multipart payload.
    public mutating func appendField(name: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        parts.append(Part(name: name, filename: nil, contentType: nil, data: data))
    }

    /// Appends a binary file part to the multipart payload.
    public mutating func appendFile(name: String, filename: String, contentType: String, data: Data) {
        parts.append(Part(name: name, filename: filename, contentType: contentType, data: data))
    }

    /// Builds the multipart body data and returns it together with the Content-Type header value.
    public func build() -> (data: Data, contentType: String) {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        for part in parts {
            body.append(boundaryPrefix.data(using: .utf8)!)

            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append("\(disposition)\r\n".data(using: .utf8)!)

            if let contentType = part.contentType {
                body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
            } else {
                body.append("\r\n".data(using: .utf8)!)
            }

            body.append(part.data)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let contentType = "multipart/form-data; boundary=\(boundary)"
        return (body, contentType)
    }

    public static func makeBoundary() -> String {
        "----ai-sdk-boundary-\(UUID().uuidString)"
    }
}
