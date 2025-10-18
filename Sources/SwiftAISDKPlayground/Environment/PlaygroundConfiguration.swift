import Foundation

struct PlaygroundConfiguration {
    struct ProviderKeys {
        var gateway: String?
        var openAI: String?
        var anthropic: String?
        var google: String?
        var groq: String?
    }

    let keys: ProviderKeys
    let defaultProvider: String
    let baseURLOverrides: [String: URL]
    let environment: PlaygroundEnvironment

    init(environment: PlaygroundEnvironment, defaultProvider: String = "gateway") {
        self.defaultProvider = defaultProvider
        self.environment = environment
        self.keys = ProviderKeys(
            gateway: environment["VERCEL_AI_API_KEY"] ?? environment["AI_GATEWAY_API_KEY"],
            openAI: environment["OPENAI_API_KEY"],
            anthropic: environment["ANTHROPIC_API_KEY"],
            google: environment["GOOGLE_API_KEY"],
            groq: environment["GROQ_API_KEY"]
        )

        var overrides: [String: URL] = [:]
        if let rawGatewayURL = environment["VERCEL_AI_BASE_URL"] ?? environment["AI_GATEWAY_BASE_URL"],
           let url = URL(string: rawGatewayURL) {
            overrides["gateway"] = url
        }
        if let openAIBase = environment["OPENAI_BASE_URL"], let url = URL(string: openAIBase) {
            overrides["openai"] = url
        }
        if let anthropicBase = environment["ANTHROPIC_BASE_URL"], let url = URL(string: anthropicBase) {
            overrides["anthropic"] = url
        }
        if let googleBase = environment["GOOGLE_AI_BASE_URL"], let url = URL(string: googleBase) {
            overrides["google"] = url
        }
        if let groqBase = environment["GROQ_BASE_URL"], let url = URL(string: groqBase) {
            overrides["groq"] = url
        }
        self.baseURLOverrides = overrides
    }
}

@MainActor
struct PlaygroundContext {
    let configuration: PlaygroundConfiguration
    let logger: PlaygroundLogger

    static var shared: PlaygroundContext?
}
