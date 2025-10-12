import Foundation

public struct EventSourceMessage: Equatable, Sendable {
    public var id: String?
    public var event: String?
    public var data: String
    public init(id: String? = nil, event: String? = nil, data: String) {
        self.id = id
        self.event = event
        self.data = data
    }
}

public enum ParseErrorKind: Equatable, Sendable {
    case invalidRetry(value: String, line: String)
    case unknownField(field: String, value: String, line: String)
}

public struct ParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public let kind: ParseErrorKind
    public var description: String {
        switch kind {
        case .invalidRetry(let value, let line):
            return "Invalid `retry` value: \(value) (line: \(line))"
        case .unknownField(let field, _, _):
            return "Unknown field \(field)"
        }
    }
    public init(_ kind: ParseErrorKind) { self.kind = kind }
}

public struct ParserCallbacks {
    public var onEvent: (EventSourceMessage) -> Void
    public var onError: (ParseError) -> Void
    public var onRetry: (Int) -> Void
    public var onComment: ((String) -> Void)?
    public init(
        onEvent: @escaping (EventSourceMessage) -> Void,
        onError: @escaping (ParseError) -> Void = { _ in },
        onRetry: @escaping (Int) -> Void = { _ in },
        onComment: ((String) -> Void)? = nil
    ) {
        self.onEvent = onEvent
        self.onError = onError
        self.onRetry = onRetry
        self.onComment = onComment
    }
}
