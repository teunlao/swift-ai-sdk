import Foundation

actor URLRequestCapture {
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }

    func first() -> URLRequest? {
        requests.first
    }

    func all() -> [URLRequest] {
        requests
    }
}

struct MultipartPart {
    let headers: [String: String]
    let body: Data
}

func extractBoundary(from contentType: String) -> String? {
    guard let range = contentType.range(of: "boundary=") else { return nil }
    let tail = contentType[range.upperBound...]
    return tail.split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "\t" }).first.map(String.init)
}

func parseMultipart(_ data: Data, boundary: String) -> [MultipartPart] {
    let bytes = [UInt8](data)
    let boundaryBytes = Array("--\(boundary)".utf8)

    guard !boundaryBytes.isEmpty, bytes.count >= boundaryBytes.count else {
        return []
    }

    var positions: [Int] = []
    var index = 0

    while index <= bytes.count - boundaryBytes.count {
        var isMatch = true

        for offset in 0..<boundaryBytes.count where bytes[index + offset] != boundaryBytes[offset] {
            isMatch = false
            break
        }

        if isMatch {
            positions.append(index)
            index += boundaryBytes.count
        } else {
            index += 1
        }
    }

    guard positions.count >= 2 else { return [] }

    var parts: [MultipartPart] = []

    for positionIndex in 0..<(positions.count - 1) {
        let start = positions[positionIndex] + boundaryBytes.count
        let end = positions[positionIndex + 1]

        if start >= end {
            continue
        }

        var partStart = start
        if partStart + 1 < end, bytes[partStart] == 0x0D, bytes[partStart + 1] == 0x0A {
            partStart += 2
        }

        var partEnd = end
        if partEnd - 2 >= partStart, bytes[partEnd - 2] == 0x0D, bytes[partEnd - 1] == 0x0A {
            partEnd -= 2
        }

        if partStart >= partEnd {
            continue
        }

        let partData = Data(bytes[partStart..<partEnd])
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])

        guard let separatorRange = partData.range(of: separator) else {
            continue
        }

        let headerData = partData.subdata(in: partData.startIndex..<separatorRange.lowerBound)
        let bodyData = partData.subdata(in: separatorRange.upperBound..<partData.endIndex)
        let headerString = String(data: headerData, encoding: .utf8) ?? ""

        var headers: [String: String] = [:]
        for rawLine in headerString.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        parts.append(MultipartPart(headers: headers, body: bodyData))
    }

    return parts
}

func multipartName(_ part: MultipartPart) -> String? {
    multipartDispositionValue(part, key: "name")
}

func multipartFilename(_ part: MultipartPart) -> String? {
    multipartDispositionValue(part, key: "filename")
}

private func multipartDispositionValue(_ part: MultipartPart, key: String) -> String? {
    guard let disposition = part.headers["content-disposition"] else { return nil }
    guard let range = disposition.range(of: "\(key)=\"") else { return nil }
    let tail = disposition[range.upperBound...]
    guard let endQuote = tail.firstIndex(of: "\"") else { return nil }
    return String(tail[..<endQuote])
}
