import Foundation

struct PlaygroundVersion: CustomStringConvertible {
    let description: String

    static let current: PlaygroundVersion = {
        // Keep the version decoupled for easy bumping.
        PlaygroundVersion(description: "0.1.0")
    }()
}
