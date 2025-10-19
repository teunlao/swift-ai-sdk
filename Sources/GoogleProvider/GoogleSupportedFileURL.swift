import Foundation

func isGoogleSupportedFileURL(_ url: URL) -> Bool {
    let urlString = url.absoluteString

    if urlString.lowercased().hasPrefix("https://generativelanguage.googleapis.com/v1beta/files/") {
        return true
    }

    let patterns = [
        "^https://(?:www\\.)?youtube\\.com/watch\\?v=[A-Za-z0-9_-]+(?:&[A-Za-z0-9_=&.-]*)?$",
        "^https://youtu\\.be/[A-Za-z0-9_-]+(?:\\?[A-Za-z0-9_=&.-]*)?$"
    ]

    return patterns.contains { pattern in
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .firstMatch(in: urlString, range: NSRange(location: 0, length: urlString.count)) != nil
    }
}
