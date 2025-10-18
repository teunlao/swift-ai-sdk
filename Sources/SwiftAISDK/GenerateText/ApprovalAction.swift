import Foundation

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public enum ApprovalAction: Sendable {
    case approve
    case deny
}
