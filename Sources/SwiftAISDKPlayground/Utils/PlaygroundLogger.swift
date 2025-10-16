import Foundation

actor PlaygroundLogger {
    static let shared = PlaygroundLogger()

    private var verboseMode: Bool = false

    func setVerbose(_ enabled: Bool) {
        verboseMode = enabled
    }

    func log(_ message: String) {
        print(message)
    }

    func verbose(_ message: String) {
        guard verboseMode else { return }
        print("[debug] \(message)")
    }

    func printError(_ error: Error) {
        fputs("error: \(error.localizedDescription)\n", stderr)
    }
}
